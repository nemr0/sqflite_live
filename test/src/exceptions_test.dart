import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_live/src/exceptions/failure_abs.dart';
import 'package:sqflite_live/src/exceptions/file_failure.dart';
import 'package:sqflite_live/src/exceptions/server_failure.dart';

void main() {
  group('Failure (abstract base)', () {
    test('stores message and null stackTrace by default', () {
      const failure = FileFailure('test message');
      expect(failure.message, 'test message');
      expect(failure.stackTrace, isNull);
    });

    test('stores provided stackTrace', () {
      final st = StackTrace.current;
      final failure = FileFailure('msg', stackTrace: st);
      expect(failure.stackTrace, same(st));
    });

    test('is a Failure subtype', () {
      const failure = FileFailure('msg');
      expect(failure, isA<Failure>());
    });
  });

  group('FileFailure', () {
    test('equality: two instances with same message are equal', () {
      const a = FileFailure('same message');
      const b = FileFailure('same message');
      expect(a, equals(b));
    });

    test('equality: identical instance equals itself', () {
      const a = FileFailure('msg');
      // ignore: unrelated_type_equality_checks
      expect(a == a, isTrue);
    });

    test('equality: different message produces not-equal', () {
      const a = FileFailure('msg A');
      const b = FileFailure('msg B');
      expect(a, isNot(equals(b)));
    });

    test('equality: different type produces not-equal', () {
      const a = FileFailure('same');
      const b = ServerFailure('same');
      expect(a, isNot(equals(b)));
    });

    test('equality: same message and same stackTrace are equal', () {
      final st = StackTrace.current;
      final a = FileFailure('msg', stackTrace: st);
      final b = FileFailure('msg', stackTrace: st);
      expect(a, equals(b));
    });

    test('equality: same message but different stackTrace are not equal', () {
      final st1 = StackTrace.current;
      final st2 = StackTrace.current;
      final a = FileFailure('msg', stackTrace: st1);
      final b = FileFailure('msg', stackTrace: st2);
      // Only equal if identical stackTrace objects are used, different objects differ
      expect(a == b, st1 == st2);
    });

    test('hashCode: equal objects have equal hashCodes', () {
      const a = FileFailure('hash test');
      const b = FileFailure('hash test');
      expect(a.hashCode, equals(b.hashCode));
    });

    test('hashCode: computed from message and stackTrace', () {
      const failure = FileFailure('hash me');
      final expected = 'hash me'.hashCode ^ null.hashCode;
      expect(failure.hashCode, equals(expected));
    });

    test('toString: includes class name, message, and stackTrace', () {
      const failure = FileFailure('something went wrong');
      expect(failure.toString(), contains('FileFailure'));
      expect(failure.toString(), contains('something went wrong'));
      expect(failure.toString(), contains('null'));
    });

    test('toString: includes stackTrace when provided', () {
      final st = StackTrace.current;
      final failure = FileFailure('err', stackTrace: st);
      expect(failure.toString(), contains('FileFailure'));
      expect(failure.toString(), contains('err'));
      expect(failure.toString(), contains(st.toString()));
    });

    test('equality: non-Failure object is not equal', () {
      const failure = FileFailure('msg');
      expect(failure == 'not a failure', isFalse);
      expect(failure == 42, isFalse);
    });
  });

  group('ServerFailure', () {
    test('equality: two instances with same message are equal', () {
      const a = ServerFailure('same message');
      const b = ServerFailure('same message');
      expect(a, equals(b));
    });

    test('equality: identical instance equals itself', () {
      const a = ServerFailure('msg');
      expect(a == a, isTrue);
    });

    test('equality: different message produces not-equal', () {
      const a = ServerFailure('msg A');
      const b = ServerFailure('msg B');
      expect(a, isNot(equals(b)));
    });

    test('equality: different type produces not-equal', () {
      const a = ServerFailure('same');
      const b = FileFailure('same');
      expect(a, isNot(equals(b)));
    });

    test('equality: same message and same stackTrace are equal', () {
      final st = StackTrace.current;
      final a = ServerFailure('msg', stackTrace: st);
      final b = ServerFailure('msg', stackTrace: st);
      expect(a, equals(b));
    });

    test('hashCode: equal objects have equal hashCodes', () {
      const a = ServerFailure('hash test');
      const b = ServerFailure('hash test');
      expect(a.hashCode, equals(b.hashCode));
    });

    test('hashCode: computed from message and stackTrace', () {
      const failure = ServerFailure('hash me');
      final expected = 'hash me'.hashCode ^ null.hashCode;
      expect(failure.hashCode, equals(expected));
    });

    test('toString: includes class name, message, and stackTrace', () {
      const failure = ServerFailure('server broke');
      expect(failure.toString(), contains('ServerFailure'));
      expect(failure.toString(), contains('server broke'));
      expect(failure.toString(), contains('null'));
    });

    test('toString: format matches expected pattern', () {
      const failure = ServerFailure('err');
      expect(failure.toString(), equals('ServerFailure{message: err, stackTrace: null}'));
    });

    test('equality: non-Failure object is not equal', () {
      const failure = ServerFailure('msg');
      expect(failure == 'not a failure', isFalse);
      expect(failure == 0, isFalse);
    });

    test('is a Failure subtype', () {
      const failure = ServerFailure('msg');
      expect(failure, isA<Failure>());
    });

    // Regression: ensure no equatable dependency — Failure is a plain class now
    test('Failure is not an Equatable (no props getter)', () {
      const failure = FileFailure('msg');
      expect(() => (failure as dynamic).props, throwsNoSuchMethodError);
    });
  });
}