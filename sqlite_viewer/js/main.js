"use strict";

const SQL_WASM_PATH = "https://inloop.github.io/sqlite-viewer/js/sql-wasm.wasm";

const SQL_FROM_REGEX = /FROM\s+((?=['"])((["'])(?<g1>[^'"]+))|(?<g2>\w+))/im;
const SQL_LIMIT_REGEX = /LIMIT\s+(\d+)(?:\s*,\s*(\d+))?/im;
const SQL_SELECT_REGEX = /SELECT\s+[^;]+\s+FROM\s+/im;

let db = null;
let lastCachedQueryCount = { select: "", count: 0 };
let loadedTableNames = [];
const editor = ace.edit("sql-editor");
const errorBox = $("#error");
const infoBox = $("#info");

const selectFormatter = function (item) {
  const index = item.text.indexOf("(");
  if (index > -1) {
    const name = item.text.substring(0, index);
    const tableName = item.text.substring(index - 1);
    return $(
      `<span>${name}<span style="color:#ccc">${tableName}</span></span>`
    );
  } else {
    return item.text;
  }
};

initialize();

function initialize() {
  let toggleFullScreen = function () {
    const container = $("#main-container");
    const resizerExpandIcon = $("#resizer-expand");
    const resizerCollapseIcon = $("#resizer-collapse");

    container.toggleClass("container container-fluid");
    resizerExpandIcon.toggle();
    resizerCollapseIcon.toggle();
  };
  $("#resizer").click(toggleFullScreen);
  $("#sql-editor").keydown(onKeyDown);

  if (typeof WebAssembly === "undefined") {
    $("#compat-error").toggleClass("d-none", false);
  } else {
    reloadDB(startAutoRefresh);
  }

  //Initialize editor
  editor.setTheme("ace/theme/chrome");
  editor.renderer.setShowGutter(false);
  editor.renderer.setShowPrintMargin(false);
  editor.renderer.setPadding(20);
  editor.renderer.setScrollMargin(8, 8, 0, 0);
  editor.setHighlightActiveLine(false);
  editor.getSession().setUseWrapMode(true);
  editor.getSession().setMode("ace/mode/sql");
  editor.setOptions({ maxLines: 5 });
  editor.setFontSize(16);

  $(".no-propagate").on("click", function (el) {
    el.stopPropagation();
  });
}

function loadDB(arrayBuffer, onLoaded, preserveQuery) {
  setIsLoading(true);

  // When refreshing in place (auto-refresh / after a write) keep the user where
  // they were instead of snapping back to the first table's default select.
  const prevQuery = preserveQuery ? editor.getValue() : null;
  const prevTable = preserveQuery ? $("#tables").val() : null;

  resetTableList();

  initSqlJs({ locateFile: (file) => SQL_WASM_PATH }).then(function (SQL) {
    let tables = null;
    try {
      db = new SQL.Database(new Uint8Array(arrayBuffer));

      //Get all table names from master table
      tables = db.prepare(
        "SELECT * FROM sqlite_master WHERE type='table' OR type='view' ORDER BY name"
      );
    } catch (ex) {
      if (tables !== null) {
        tables.free();
      }
      setIsLoading(false);
      window.alert(ex);
      return;
    }

    let firstTableName = null;
    const tableList = $("#tables");

    while (tables.step()) {
      const rowObj = tables.getAsObject();
      const name = rowObj["name"];
      const type = rowObj["type"];

      if (firstTableName === null) {
        firstTableName = name;
      }
      const rowCount = getTableRowsCount(name);
      loadedTableNames.push(name);
      const tableType = type !== "table" ? `, ${type}` : "";
      tableList.append(
        `<option value="${name}">${name} (${rowCount} rows${tableType})</option>`
      );
    }
    tables.free();

    // Restore the previous view when refreshing in place; otherwise select the
    // first table and show its default query.
    if (prevQuery && loadedTableNames.indexOf(prevTable) > -1) {
      tableList.val(prevTable);
      lastCachedQueryCount = { select: "", count: 0 };
      renderQuery(prevQuery);
    } else {
      tableList.val(firstTableName);
      doDefaultSelect(firstTableName);
    }

    $("#output-box").fadeIn();
    $("#success-box").show();

    setIsLoading(false);
    if (typeof onLoaded === "function") onLoaded();
  });
}

// Re-fetches cached.db from the server and reloads it into the in-memory
// database, so the view reflects the real database after a server-side write.
// Cache-busted so the browser never serves a stale copy.
function reloadDB(onLoaded, preserveQuery) {
  setIsLoading(true);
  const xhr = new XMLHttpRequest();
  xhr.open("GET", "cached.db?_=" + Date.now(), true);
  xhr.responseType = "arraybuffer";
  xhr.onload = function () {
    if (this.status === 200) {
      loadDB(this.response, onLoaded, preserveQuery);
    } else {
      showError("Failed to load database: cached.db. Status: " + this.status);
      setIsLoading(false);
    }
  };
  xhr.onerror = function () {
    showError("Error occurred while trying to fetch cached.db.");
    setIsLoading(false);
  };
  xhr.send();
}

// Polls the server for the database signature and reloads the view in place
// whenever the app mutates the database, so changes made inside the app (not
// just through this viewer) show up without a manual page refresh.
const AUTO_REFRESH_MS = 2000;
let lastDbVersion = null;
let autoReloadInFlight = false;
let autoReloadStartedAt = 0;

function startAutoRefresh() {
  setInterval(pollDbVersion, AUTO_REFRESH_MS);
}

function pollDbVersion() {
  // Self-heal: if a reload never reported back (e.g. it errored out), don't
  // block auto-refresh forever.
  if (autoReloadInFlight && Date.now() - autoReloadStartedAt > 10000) {
    autoReloadInFlight = false;
  }
  if (autoReloadInFlight) return;
  fetch("db-version?_=" + Date.now())
    .then(function (res) {
      return res.json();
    })
    .then(function (v) {
      if (v.error) return;
      const signature = v.size + ":" + v.modified;
      // Seed on the first poll so we don't reload on initial load.
      if (lastDbVersion === null) {
        lastDbVersion = signature;
        return;
      }
      if (signature === lastDbVersion) return;
      // Record the new signature up front so we don't re-trigger on the next
      // poll for the same change.
      lastDbVersion = signature;
      autoReloadInFlight = true;
      autoReloadStartedAt = Date.now();
      reloadDB(function () {
        autoReloadInFlight = false;
      }, true);
    })
    .catch(function () {
      // Server briefly unreachable (e.g. app resuming) — try again next tick.
    });
}

function getTableRowsCount(name) {
  const sel = db.prepare(`SELECT COUNT(*) AS count FROM '${name}'`);
  if (sel.step()) {
    const count = sel.getAsObject()["count"];
    sel.free();
    return count;
  } else {
    sel.free();
    return -1;
  }
}

function getQueryRowCount(query) {
  if (query === lastCachedQueryCount.select) {
    return lastCachedQueryCount.count;
  }

  let queryReplaced = query.replace(
    SQL_SELECT_REGEX,
    "SELECT COUNT(*) AS count FROM "
  );

  if (queryReplaced !== query) {
    queryReplaced = queryReplaced.replace(SQL_LIMIT_REGEX, "");
    const sel = db.prepare(queryReplaced);
    if (sel.step()) {
      const count = sel.getAsObject()["count"];
      sel.free();

      lastCachedQueryCount.select = query;
      lastCachedQueryCount.count = count;

      return count;
    } else {
      sel.free();
      return -1;
    }
  } else {
    return -1;
  }
}

function getTableColumnTypes(tableName) {
  let result = new Map();
  const sel = db.prepare(`PRAGMA table_info('${tableName}')`);

  while (sel.step()) {
    const obj = sel.getAsObject();
    let type = obj["type"];
    if (obj["notnull"] === 1) {
      type += " NOT NULL";
    }
    if (obj["pk"] === 1) {
      type += " PRIMARY KEY";
    }
    result.set(obj.name, type);
  }
  sel.free();

  return result;
}

function resetTableList() {
  const tables = $("#tables");
  loadedTableNames = [];
  tables.empty();
  tables.append("<option></option>");
  tables.select2({
    placeholder: "Select a table",
    theme: "bootstrap-5",
    templateSelection: selectFormatter,
    templateResult: selectFormatter,
  });
  tables.on("change", function (e) {
    doDefaultSelect(tables.val());
  });
}

function setIsLoading(isLoading) {
  const globalLoading = $("#global-loading");

  if (globalLoading.length) {
    if (isLoading) {
      globalLoading.removeClass("d-none");
    } else {
      globalLoading.addClass("d-none");
    }
  }
}

function doDefaultSelect(name) {
  const defaultSelect = `SELECT * FROM '${name}' LIMIT 0,30`;
  editor.setValue(defaultSelect, -1);
  renderQuery(defaultSelect);
}

function executeSql() {
  const query = editor.getValue();
  const head = query.trimStart().toUpperCase();
  const isQuery =
    head.startsWith("SELECT") ||
    head.startsWith("PRAGMA") ||
    head.startsWith("EXPLAIN") ||
    head.startsWith("WITH");

  if (isQuery) {
    // Read-only: run locally against the in-memory copy.
    renderQuery(query);
    $("#tables").val(getTableNameFromQuery(query));
    return;
  }

  // Mutation: run it on the real database via the server, then reload so the
  // view reflects the persisted change.
  runServerExec(query);
}

// POSTs a mutating statement to the server's /exec endpoint (which runs it on
// the app's live database), then re-fetches the database and reports how many
// rows were affected.
function runServerExec(query) {
  setIsLoading(true);
  fetch("exec", {
    method: "POST",
    headers: { "Content-Type": "text/plain" },
    body: query,
  })
    .then(function (res) {
      return res.json().then(function (json) {
        return { ok: res.ok, json: json };
      });
    })
    .then(function (result) {
      if (!result.ok || result.json.error) {
        setIsLoading(false);
        showError(result.json.error || "Server returned an error.");
        return;
      }
      const affected = result.json.rowsAffected || 0;
      reloadDB(function () {
        infoBox.text(affected + " row(s) affected.");
        infoBox.show();
      });
    })
    .catch(function (err) {
      setIsLoading(false);
      showError(err);
    });
}

function getTableNameFromQuery(query) {
  const sqlRegex = SQL_FROM_REGEX.exec(query);
  if (sqlRegex != null) {
    return sqlRegex.groups.g1 ?? sqlRegex.groups.g2;
  } else {
    return null;
  }
}

function parseLimitFromQuery(query) {
  const sqlRegex = SQL_LIMIT_REGEX.exec(query);
  if (sqlRegex != null) {
    let result = { max: 0, offset: 0 };

    if (sqlRegex.length > 2 && typeof sqlRegex[2] !== "undefined") {
      result.offset = parseInt(sqlRegex[1]);
      result.max = parseInt(sqlRegex[2]);
    } else {
      result.offset = 0;
      result.max = parseInt(sqlRegex[1]);
    }

    if (result.max == 0) {
      result.pages = 0;
      result.currentPage = 0;
      return result;
    }

    const queryRowsCount = getQueryRowCount(query);
    if (queryRowsCount != -1) {
      result.pages = Math.ceil(queryRowsCount / result.max);
    }
    result.currentPage = Math.floor(result.offset / result.max) + 1;
    result.rowCount = queryRowsCount;

    return result;
  } else {
    return null;
  }
}

function setPage(el, next) {
  if ($(el).hasClass("disabled")) return;

  const query = editor.getValue();
  const limit = parseLimitFromQuery(query);

  let pageToSet = 0;
  if (typeof next !== "undefined") {
    pageToSet = next ? limit.currentPage : limit.currentPage - 2;
  } else {
    const page = window.prompt("Go to page");
    if (!isNaN(page) && page >= 1 && page <= limit.pages) {
      pageToSet = page - 1;
    } else {
      return;
    }
  }

  const offset = pageToSet * limit.max;
  editor.setValue(
    query.replace(SQL_LIMIT_REGEX, `LIMIT ${offset},${limit.max}`),
    -1
  );

  executeSql();
}

function refreshPagination(query) {
  const limit = parseLimitFromQuery(query);
  if (limit !== null && limit.pages > 0) {
    const pager = $("#pager");
    const pagePrev = $("#page-prev");
    const pageNext = $("#page-next");

    pager.attr("title", `Row count: ${limit.rowCount}`);
    bootstrap.Tooltip.getOrCreateInstance("#pager").hide();
    pager.text(limit.currentPage + " / " + limit.pages);

    if (limit.currentPage <= 1) {
      pagePrev.addClass("disabled");
    } else {
      pagePrev.removeClass("disabled");
    }

    if (limit.currentPage + 1 > limit.pages) {
      pageNext.addClass("disabled");
    } else {
      pageNext.removeClass("disabled");
    }

    setPagerVisible(true);
  } else {
    setPagerVisible(false);
  }
}

function showError(msg) {
  $("#data").hide();
  setPagerVisible(false);
  errorBox.show();
  errorBox.text(msg);
}

function setPagerVisible(visible) {
  $("#bottom-bar").toggleClass("d-none", !visible);
  if (visible) {
    $("#footer").attr("style", "margin-top: -0.75rem !important");
  } else {
    $("#footer").css("margin-top", "");
  }
}

function htmlEncode(value) {
  return $("<div/>").text(value).html();
}

function renderQuery(query) {
  const dataBox = $("#data");
  const thead = dataBox.find("thead").find("tr");
  const tbody = dataBox.find("tbody");

  thead.empty();
  tbody.empty();
  errorBox.hide();
  infoBox.hide();
  dataBox.show();

  let columnTypes = new Map();
  const tableName = getTableNameFromQuery(query);
  if (tableName != null) {
    columnTypes = getTableColumnTypes(tableName);
  }

  let sel = null;
  try {
    sel = db.prepare(query);
  } catch (ex) {
    if (sel != null) {
      sel.free();
    }
    showError(ex);
    return;
  }

  let isEmptyTable = true;
  const columnNames = sel.getColumnNames();
  for (let i = 0; i < columnNames.length; i++) {
    const columnName = columnNames[i];
    const type = columnTypes.has(columnName)
      ? columnTypes.get(columnNames[i])
      : "";
    thead.append(
      `<th><span data-bs-toggle="tooltip" title="${type}">${columnNames[i]}</span></th>`
    );
  }

  while (sel.step()) {
    isEmptyTable = false;
    const tr = $("<tr>");
    const s = sel.get();
    for (let i = 0; i < s.length; i++) {
      const columnName = columnNames[i];
      const type = columnTypes.has(columnName)
        ? columnTypes.get(columnName).toLowerCase()
        : "";
      if (type === "blob" || type === "blob sub_type binary") {
        if (s[i] === null) {
          tr.append(`<td><span title="Blob">null</span></td>`);
        } else {
          renderBlobItem(tr, s[i]);
        }
      } else {
        let value = htmlEncode(s[i]);
        tr.append(`<td><span title="${value}">${value}</span></td>`);
      }
    }
    tbody.append(tr);
  }
  sel.free();

  if (isEmptyTable) {
    infoBox.text("No data for given select.");
    infoBox.show();
  }

  refreshPagination(query);

  // Enable tooltips
  document
    .querySelectorAll('[data-bs-toggle="tooltip"]')
    .forEach((tooltipTriggerEl) => new bootstrap.Tooltip(tooltipTriggerEl));

  dataBox.editableTableWidget();
}

function renderBlobItem(tr, bytes) {
  const td = document.createElement("td");
  const span = document.createElement("span");
  span.title = "Blob";
  const downloadLink = document.createElement("a");
  downloadLink.href = "javascript:void(0)";
  downloadLink.innerText = `Download (${formatBytes(bytes.length)})`;
  downloadLink.onclick = function () {
    saveAs(new Blob([bytes]), "blob");
  };
  span.append(downloadLink);
  td.append(span);
  tr.append(td);
}

function formatBytes(bytes, decimals) {
  if (bytes === 0) return "0 Bytes";
  const k = 1024,
    dm = decimals || 2,
    sizes = ["Bytes", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"],
    i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + " " + sizes[i];
}

function onKeyDown(e) {
  if ((e.ctrlKey || e.metaKey) && e.key === "Enter") {
    executeSql();
  }
}

function arrayToCsv(data) {
  return data
    .map(
      (row) =>
        row
          .map(String) // convert every value to String
          .map((v) => v.replaceAll('"', '""')) // escape double quotes
          .map((v) => `"${v}"`) // quote it
          .join(",") // comma-separated
    )
    .join("\r\n"); // rows starting on new lines
}

function exportCsvTableQuery(query) {
  let exportedRows = [];
  let sel = null;
  try {
    sel = db.prepare(query);
  } catch (ex) {
    if (sel != null) {
      sel.free();
    }
    showError(ex);
    setIsLoading(false);
    return null;
  }

  const columnNames = sel.getColumnNames();

  exportedRows.push(...[columnNames]);
  while (sel.step()) {
    const rows = sel.get();
    exportedRows.push(...[rows]);
  }
  sel.free();
  return exportedRows;
}

function exportCsvTable(tableName) {
  return exportCsvTableQuery(`SELECT * FROM '${tableName}'`);
}

function exportAllToCsv() {
  setIsLoading(true);
  const zip = new JSZip();
  for (const tableName of loadedTableNames) {
    const exportedRows = exportCsvTable(tableName);
    if (exportedRows != null) {
      zip.file(tableName + ".csv", arrayToCsv(exportedRows));
    } else {
      return;
    }
  }

  zip.generateAsync({ type: "blob" }).then(function (content) {
    saveAs(content, "exported_all_db.zip");
  });
  setIsLoading(false);
}

function exportSelectedTableToCsv() {
  const tableName = $("#tables").val();
  setIsLoading(true);

  const exportedRows = exportCsvTable(tableName);
  if (exportedRows != null) {
    const blob = new Blob([arrayToCsv(exportedRows)], {
      type: "text/plain;charset=utf-8",
    });
    saveAs(blob, "exported_" + tableName.toLowerCase() + "_db.csv");
  }

  setIsLoading(false);
}

function exportQueryTableToCsv() {
  setIsLoading(true);

  const query = editor.getValue();
  const exportedRows = exportCsvTableQuery(query);
  if (exportedRows != null) {
    const blob = new Blob([arrayToCsv(exportedRows)], {
      type: "text/plain;charset=utf-8",
    });
    saveAs(
      blob,
      "exported_" + getTableNameFromQuery(query).toLowerCase() + "_db.csv"
    );
  }

  setIsLoading(false);
}
