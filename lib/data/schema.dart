import 'package:sqflite/sqflite.dart';

const schemaVersion = 1;

Future<void> createSchema(Database db, int version) async {
  await db.execute('''CREATE TABLE accounts (
    id TEXT PRIMARY KEY, name TEXT NOT NULL, currency TEXT NOT NULL
      CHECK(currency IN ('AED','BDT','PKR')),
    kind TEXT NOT NULL CHECK(kind IN ('asset','liability','external')),
    role TEXT NOT NULL, protected INTEGER NOT NULL DEFAULT 0)''');
  await db.execute('''CREATE TABLE periods (
    id INTEGER PRIMARY KEY AUTOINCREMENT, started TEXT NOT NULL,
    ended TEXT, summary TEXT)''');
  await db.execute('''CREATE TABLE cycles (
    id INTEGER PRIMARY KEY AUTOINCREMENT, started TEXT NOT NULL, ended TEXT)''');
  await db.execute('''CREATE TABLE operations (
    id TEXT PRIMARY KEY, sequence INTEGER NOT NULL UNIQUE, kind TEXT NOT NULL, occurred TEXT NOT NULL,
    created TEXT NOT NULL, period_id INTEGER NOT NULL REFERENCES periods(id),
    cycle_id INTEGER REFERENCES cycles(id), note TEXT NOT NULL DEFAULT '',
    data TEXT NOT NULL, reverses TEXT UNIQUE REFERENCES operations(id))''');
  await db.execute('''CREATE TABLE postings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    operation_id TEXT NOT NULL REFERENCES operations(id) ON DELETE CASCADE,
    account_id TEXT NOT NULL REFERENCES accounts(id),
    amount INTEGER NOT NULL CHECK(typeof(amount)='integer' AND amount != 0))''');
  await db.execute('CREATE INDEX account_postings ON postings(account_id, operation_id)');
  await db.execute('''CREATE TABLE dependencies (
    operation_id TEXT NOT NULL REFERENCES operations(id) ON DELETE CASCADE,
    requires_id TEXT NOT NULL REFERENCES operations(id),
    PRIMARY KEY(operation_id, requires_id), CHECK(operation_id != requires_id))''');
  await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
  await db.execute('''CREATE TABLE deletion_events (
    operation_key TEXT PRIMARY KEY, occurred TEXT NOT NULL, count INTEGER NOT NULL)''');
  final now = DateTime.now().toUtc().toIso8601String();
  await db.insert('periods', {'started': now});
  await db.insert('cycles', {'started': now});
  for (final account in initialAccounts) {
    await db.insert('accounts', account);
  }
}

const initialAccounts = <Map<String, Object>>[
  {'id':'bd_bank', 'name':'বাংলাদেশ ব্যাংক', 'currency':'BDT', 'kind':'asset', 'role':'bank'},
  {'id':'principal', 'name':'দিরহাম মূলধন', 'currency':'AED', 'kind':'asset', 'role':'principal'},
  {'id':'profit', 'name':'লাভের নগদ', 'currency':'AED', 'kind':'asset', 'role':'profit'},
  {'id':'reserve', 'name':'অন্যান্য নগদ', 'currency':'AED', 'kind':'asset', 'role':'cash'},
  {'id':'agent_payable', 'name':'এজেন্টের পাওনা', 'currency':'AED', 'kind':'liability', 'role':'agent'},
  {'id':'agent_advance', 'name':'এজেন্টের কাছে অগ্রিম', 'currency':'AED', 'kind':'asset', 'role':'advance'},
  {'id':'external_BDT', 'name':'বহিঃহিসাব BDT', 'currency':'BDT', 'kind':'external', 'role':'external', 'protected':1},
  {'id':'external_AED', 'name':'বহিঃহিসাব AED', 'currency':'AED', 'kind':'external', 'role':'external', 'protected':1},
  {'id':'external_PKR', 'name':'বহিঃহিসাব PKR', 'currency':'PKR', 'kind':'external', 'role':'external', 'protected':1},
];
