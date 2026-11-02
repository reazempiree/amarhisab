# Ledger design and boundaries

All monetary postings use integer hundredths (BDT, AED and PKR). Rates are exact
BigInt numerator/denominator pairs parsed from up to eight decimal digits. Divide
foreign minor units by the rate, round half away from zero at the AED cent
boundary, and derive profit by subtraction from the rounded customer AED amount.
No binary floating point is used for financial ledger calculations.

Asset increases are positive; liabilities increase negatively. Each operation's
postings balance to zero separately in each currency. External control accounts
balance funding, spending and currency conversion. Amounts, rates and calculated
results are retained together. Result snapshots are checked against the exact
quote and actual remittance allocations during integrity checks. Account balances
come only from SQLite postings. A single database transaction writes the operation,
postings, dependencies and saved defaults. Unique operation keys reject collisions
and make identical retries idempotent. Both final and historical account balances
are checked to prevent unfunded surviving activity after deletion or restore.

## Bangladesh

For B foreign minor units, Rb bank rate, Rc customer rate, F AED fee:

- P = round(B / Rb), C = round(B / Rc)
- exchange profit = C − P; user profit = C − P + F
- collected = C + F = P + user profit
- bank −B / external BDT +B
- principal +P / profit +user profit / external AED −collected

34,000 BDT, 34.50 bank, 34 customer, fee 5 AED gives principal 985.51,
exchange profit 14.49, user profit 19.49 and collected 1,005.00 AED.
Save means the customer has paid in full. No separate customer receipt is posted.
Negative own profit is rejected in this first version; loss-making remittances
require a separately designed funding policy.

Historical bank funding counts external deposits and their reversals. Opening
balances are entered as deposits once. Adjustments, transfers and remittances
never change this metric. Repatriation is a distinct currency conversion, not new
external funding or profit. Bank corrections post target minus current balance
against the external control account and retain before/difference/target.

## Pakistan — business policy pending

The engine accepts an **explicit AED agent commission amount** K computed by a
future confirmed business rule. No percentage or split is assumed. The UI cannot
save Pakistan remittances until that rule is confirmed and wired in.

- P = round(PKR / Rb), C = round(PKR / Rc)
- agent obligation = P + K
- user profit = C − P + F − K
- principal cash +(P+K), profit cash +user profit
- apply A = min(existing advance, P+K)
- advance −A; payable −(P+K−A); external AED −user profit

Example (test fixture, **not a chosen commercial policy**): 75,500 PKR, rates
76 / 75.50, fee 5, explicitly supplied agent commission 2 AED gives P 993.42,
C 1,000.00, own profit 9.58 and obligation 995.42 AED.

Payment X uses funded AED cash exactly once. The first min(X, payable) clears debt;
the excess is an advance asset. A later liability consumes that advance once.
Refunds move actual advance money back to selected cash. Agent operations record
explicit dependencies on earlier relationship operations. An agent cycle can close
only when payable and advance are both zero; history remains. General receivables
and payables use separate cash/obligation transfers, not customer-credit remittances.

## Periods and corrections

Period close requires reconciliation, moves actual remaining profit cash to
principal and stores period totals and closing balances. It does not create
another profit receipt or change cash in total. Spent profit stays spent. Partial
withdrawals, expenses or repatriations are recorded as real transactions before
closure; only the remainder moves. Agent debt and advances carry forward.

Cancellation posts an auditable inverse operation. A single unique reversal is
allowed, dependencies can block it, and closed periods are immutable. To edit,
cancel the open operation and enter the corrected one with a new operation key.

## Permanent clearing and backup

Preview selects authoritative postings, includes both agent relationship accounts,
and covers whole operations with counterpart postings. It lists types, timestamps,
affected accounts and projected balances. It blocks closed periods, external
dependents and invalid final/historical balances. Resolution is to settle/reverse
eligible dependent open transactions first; closed periods have no silent reopen.

Before clearing, the app requests authentication if enabled, creates a password-
encrypted backup, saves it using the platform file picker, reads it back, checks
AES-GCM authentication and compares the decrypted snapshot. The resulting
capability is tied to the complete database state, checked again under the SQLite
write transaction. DELETE is required. Deletion removes complete operations and
postings, validates survivors and retains only time/count/operation-key metadata.
SQLite secure_delete, WAL checkpoint and VACUUM remove active storage remnants;
external exported backups are never deleted. Restoring one can reintroduce records.

Backups use AES-256-GCM, random salt/nonce and PBKDF2-HMAC-SHA256 with 210,000
iterations. Passphrases are never stored. Restore is transactional, format/version
checked, validates foreign keys/accounts/postings and requires a pristine ledger.
The optional app PIN is salted/derived and stored in Android secure storage, with
attempt throttling; biometrics are optional. The complete Navigator is obscured
when a protected app is paused. Android automatic app-data backup is disabled.
The SQLite file itself is not encrypted; device security and the app PIN are not
an equivalent to SQLCipher encryption. Exported backups are encrypted.

## Migration and delivery boundary

Schema version 1 is a fresh database. No old production schema or encrypted backup
sample was supplied, so no legacy import or production-upgrade compatibility is
claimed. Unknown formats and versions fail without wiping data. Incremental
migrations must be implemented and tested when a real version-2 schema is introduced.

New package: com.reazempire.amarhisab.fresh. This is intended for side-by-side
installation; the old package ID has not been inspected, so uniqueness against
that old app is not verified. Debug builds use a local development certificate.
Future upgrades need the same package and signing key; production signing is not
configured and no private key is checked in. Do not uninstall the old app.
