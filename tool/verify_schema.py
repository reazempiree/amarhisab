"""Exercise the actual SQLite DDL without claiming to execute Dart business logic."""
from pathlib import Path
import re
import sqlite3
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'lib/data/schema.dart'
SQL = re.findall(r"await db\.execute\('''(.*?)'''\);|await db\.execute\('([^'\n]*)'\);", SOURCE.read_text(), re.S)

class SchemaTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(':memory:')
        self.db.execute('PRAGMA foreign_keys=ON')
        for triple, single in SQL:
            self.db.execute(triple or single)
        self.db.execute("INSERT INTO accounts(id,name,currency,kind,role) VALUES('cash','cash','AED','asset','cash')")
        self.db.execute("INSERT INTO periods(started) VALUES('2026-11-02T00:00:00Z')")
        self.db.execute("INSERT INTO cycles(started) VALUES('2026-11-02T00:00:00Z')")
        self.db.execute("INSERT INTO operations(id,sequence,kind,occurred,created,period_id,cycle_id,data) VALUES('one',1,'deposit','now','now',1,1,'{}')")
        self.db.commit()
    def tearDown(self):
        self.db.close()
    def test_foreign_keys_reject_orphan_posting(self):
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO postings(operation_id,account_id,amount) VALUES('missing','cash',100)")
    def test_integer_and_nonzero_constraints(self):
        for value in (0,1.5,'bad'):
            with self.assertRaises(sqlite3.IntegrityError):
                self.db.execute("INSERT INTO postings(operation_id,account_id,amount) VALUES('one','cash',?)",(value,))
    def test_duplicate_operation_key_rejected(self):
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("INSERT INTO operations SELECT * FROM operations WHERE id='one'")
    def test_linked_postings_cascade_atomically(self):
        self.db.execute("INSERT INTO postings(operation_id,account_id,amount) VALUES('one','cash',100)")
        self.db.commit()
        try:
            with self.db:
                self.db.execute("DELETE FROM operations WHERE id='one'")
                raise RuntimeError('injected failure')
        except RuntimeError:
            pass
        self.assertEqual(self.db.execute('SELECT amount FROM postings').fetchall(),[(100,)])
        with self.db:
            self.db.execute("DELETE FROM operations WHERE id='one'")
        self.assertEqual(self.db.execute('SELECT * FROM postings').fetchall(),[])
    def test_dependency_blocks_parent_deletion(self):
        self.db.execute("INSERT INTO operations(id,sequence,kind,occurred,created,period_id,cycle_id,data) VALUES('two',2,'agent_payment','now','now',1,1,'{}')")
        self.db.execute("INSERT INTO dependencies VALUES('two','one')")
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("DELETE FROM operations WHERE id='one'")
    def test_single_reversal_reference(self):
        for key in ('two','three'):
            self.db.execute("INSERT INTO operations(id,sequence,kind,occurred,created,period_id,cycle_id,data) VALUES(?,?,'reversal','now','now',1,1,'{}')",(key,2 if key=='two' else 3))
        self.db.execute("UPDATE operations SET reverses='one' WHERE id='two'")
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute("UPDATE operations SET reverses='one' WHERE id='three'")

if __name__ == '__main__':
    unittest.main(verbosity=2)
