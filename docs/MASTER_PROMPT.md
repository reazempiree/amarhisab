# CODEX MASTER PROMPT — AMAR HISAB (আমার হিসাব)
## Build a NEW, production-quality offline Bengali Android remittance accounting app

READ THE ENTIRE SPECIFICATION BEFORE WRITING CODE. Implement actual working software, tests, and a verifiable APK, not a mockup or isolated snippets.

## 1. Project mode and delivery
The user explicitly wants a NEW Flutter Android application, rather than further patching the previous broken build. Create a new repository/project only in the repository/workspace authorized by the user. Never delete or overwrite the previous project or its financial records. Ask for the destination repository only if it is not already provided by the Codex environment. Preserve a pathway to import the old app's encrypted backups if their format can be verified; do not assume compatibility or claim restored data without testing. Use a new package ID if necessary to allow side-by-side installation with the old app. Explain the package/signing decision and its effect on upgrades and data before delivery.

App name: আমার হিসাব (Amar Hisab)
Platform: Android, Flutter/Dart, SQLite, offline-first
Primary language: Bengali, Noto Serif Bengali font
Currencies: BDT, AED, PKR
Use precise integer minor units and decimal/rational exchange-rate calculations; no floating-point financial ledger.

## 2. Core operating model
This is a UAE-based operator's ledger for funded remittances to Bangladesh and Pakistan. The customer AED payment must be received before a remittance is completed; there is NO customer-credit workflow. A successful Save represents a fully funded, completed remittance. The Save operation atomically posts all related debits, credits, profit and obligations exactly once. No mandatory customer name, account number, status checkbox or extra confirmation step in the simplified remittance forms. Prevent double taps and duplicate transactions. Persist all changes immediately.

Accounts initially: Bangladesh bank (BDT), AED principal cash, AED profit cash, optional general AED cash/agent reserve, Pakistan agent payable and agent advance. Architecture must allow multiple banks and wallets later. Keep receivables/payables and agent settlement distinct from customer-credit remittances.

## 3. Visual design — mandatory
Premium soft black-and-white mobile-first interface, white/off-white backgrounds, dark readable Bengali typography, Noto Serif Bengali, prominent bold amounts. EVERY major box/card must have a clearly visible dark/black outline, rounded corners, subtle shadow and comfortable padding. Black/charcoal selected segmented controls with white text; unselected white controls with dark text/border. Premium smooth animations, stacked/swipeable balance cards, reduced-motion support, dark mode, accessible text scaling, responsive small Android screens, no clipping or bottom-nav overlap. Floating bottom navigation: হোম, লেনদেন, অ্যাকাউন্ট, রিপোর্ট, সেটিংস. Do not replace the accounting interface with an unstyled prototype. The user may provide old screenshots/video as design reference; inspect if attached, otherwise do not pretend to have seen them.

Use Bengali numerals and labels. Whole BDT values without unnecessary .০০, but preserve fractional BDT where meaningful. AED precision to minor units. Never alter stored values for display formatting.

## 4. Dashboard
Large premium black card with selectable Bangladesh/UAE balance views. Bangladesh view clearly separates:
- মোট জমা টাকা (historical cumulative funding)
- বর্তমান ব্যালেন্স (actually spendable bank money, directly beneath cumulative deposits with subtle divider)
- রেমিট্যান্সে ব্যবহৃত (actual completed bank remittance deductions)
- Personal expenses and withdrawals where appropriate.
UAE view: AED principal cash, available profit cash, other cash/agent reserve where relevant, current-period earned profit. Quick actions: পাঠানো, জমা, খরচ, আরও. Correct country and wallet defaults. Tapping balances opens accurate account-specific histories.

Example: 90,000 BDT funding + 10,000 BDT deposit - 30,000 BDT completed remittance = cumulative deposits 100,000 BDT, available balance 70,000 BDT, remittance-used 30,000 BDT. Ordinary remittances/expenses/withdrawals/internal transfers do NOT reduce cumulative funding. Legitimate deletion/correction of a deposit can change cumulative funding. Count original opening balances exactly once; avoid double counting bank-to-bank transfers. Historical funding is NOT current net worth.

## 5. Bangladesh remittance
Exactly four main input fields: bank rate (default 34.45 BDT/AED), customer rate (default 34.00), BDT amount to send, service charge (default 5 AED); editable defaults persist separately by country. Live profit summary. For BDT amount B, bank rate Rb, customer rate Rc, fee F:
principalAED = B/Rb; customerAED = B/Rc; exchangeProfitAED = customerAED-principalAED; totalProfitAED = exchangeProfitAED+F; totalAEDCollected = customerAED+F.
Example B=34,000, Rb=34.50, Rc=34.00, F=5 => principal approx 985.51 AED, exchange profit approx 14.49 AED, total profit approx 19.49 AED, total collected 1,005 AED. Use an explicit deterministic minor-unit rounding policy and reconcile exact posted sums. On Save atomically deduct BDT from selected bank, credit AED principal cash, credit user-owned AED profit cash. Reject insufficient bank funds and invalid rates; preserve rate snapshots and audit. No invented duplicate AED receipt.

## 6. Pakistan remittance
Exactly four main fields: Pakistan agent/bank rate (default 76.00 PKR/AED), customer rate (default 75.50), PKR sent, AED service fee (editable; default 5 AED for fresh installation unless user explicitly chooses another). Preserve independent saved defaults. Live calculations and completed-on-save semantics. Model agent's commission and liabilities separately from the user's exchange profit and fee; only user-owned profit enters profit cash. Support agent settlements and advances, funded cash movements, and avoid double counting. Document precise country-specific formulas and rounding, test with worked examples. If commission-sharing policy cannot be inferred from provided source or confirmed business rules, ask the user for that single policy rather than inventing percentages.

## 7. Bank deposits, wallets, expenses, transfers
Deposit BDT to selected Bangladesh bank; editable rate/note/date where useful, recorded once. Personal expenses from BDT bank, AED principal cash, or AED profit cash; each deducts selected wallet once, supports optional category/note/date, and never changes historically earned remittance profit. Reports by day/week/month/custom period and source/currency. Genuine withdrawals and internal transfers with atomic paired postings. Internal transfers are not income or profit. Multiple account support. Distinguish current profit cash from lifetime earned profit and from agent liabilities. Maintain separate general receivables/payables.

## 8. NEW CHANGE ONE — unlimited editable Bangladesh bank current balance
At the upper-right of each Bangladesh bank card add a pencil icon as in the user's marked screenshot. Clicking opens “ব্যাংকের ব্যালেন্স সংশোধন করুন”: actual current balance, editable target balance, automatically calculated difference, optional reason, confirmation. User can edit repeatedly, not once only. Example current 130,500 BDT -> target 150,000 BDT => +19,500 BDT balance adjustment posting; target is shown immediately and persists. Implement auditable, atomic ledger adjustments, not direct silent mutation. Corrections do not automatically increase cumulative deposits, remittance profit, service-fee income or personal expense. Support multi-bank selection, reversal, idempotency, backup/restore and tests.

## 9. NEW CHANGE TWO — permanently erase all selected-account transactions
Add a clearly separated destructive action at bottom of EACH eligible account card: “সকল লেনদেন স্থায়ীভাবে মুছে ফেলুন”. User explicitly requests actual permanent removal from active database, not hiding/archiving. Implement safely:
- Resolve all selected-account transactions including modern allocations and legacy links.
- Build full dependency graph of transaction postings, counterpart accounts, profit, agent obligations, internal transfers and closed accounting periods.
- Preview transaction count, dates, categories, other affected accounts and projected balances.
- Require a successfully created AND verified encrypted backup, strong explicit confirmation (type DELETE), and PIN/biometric where enabled.
- Delete entire linked transaction and all of its postings atomically, never just one side of a double-entry remittance. Recompute all surviving balances and cumulative funding from authoritative surviving postings. Ensure foreign keys, references and audits remain consistent.
- If deletion conflicts with later settlements or closed-period snapshots, BLOCK and explain dependencies; do not silently rewrite history or invent balancing transactions. Provide explicit supported resolution steps.
- Never wipe unrelated accounts or the entire database. Deletion from active DB does not erase old exported backups; warn that restoring old backup may reintroduce records. Do not silently delete external backups.
- Keep only minimal deletion-event metadata if required; do not retain full financial transaction payload disguised as deleted records. If legal/retention constraints apply, explain them rather than silently promising irreversible deletion.
- Protect against failure midway, retries and duplicate deletes; test complete rollback and cross-account consistency.

## 10. NEW CHANGE THREE — Pakistan agent overpayment as advance
Allow payment greater than currently owed. Example payable 2,000 AED, actual payment 2,100 AED => payable 0, agent holds user's advance 100 AED. The 100 is NOT profit, personal expense or lost money. Show gross payable, paid amount, outstanding payable, advance held, advance applied, net position and payment history. If next agent liability is 500 AED, apply existing 100 AED advance once, leaving 400 AED payable. Actual 2,100 AED cash payment must debit an actually funded selected AED source exactly once. No fabricated settlement or negative balances. Include partial payments, overpayments, refunds, reversals, idempotency and persistence tests.

## 11. NEW CHANGE FOUR — settle entire agent relationship and begin a new cycle
Add “এজেন্টের সকল হিসাব নিষ্পত্তি করুন” to agent account card. Show all payable, advance, payments, refunds and net position. Support final real payment, advance refund/application or explicitly documented authorized adjustment. After genuinely settled, start fresh agent cycle showing payable 0 and advance 0. Do not erase real debt or advance merely to show zero. Preserve prior settled cycle in history unless user separately invokes explicit permanent-clear operation. If user requests permanent deletion of agent transaction history, apply the same backup, dependency analysis, preview, confirmation and atomic deletion rules as section 9; block when it would break surviving transactions or closed periods. Never alter unrelated Bangladesh bank or AED cash balances silently.

## 12. Accounting-period close and profit settlement
Provide “হিসাব বন্ধ করুন”, “বন্ধ করা হিসাবসমূহ” and “নতুন হিসাব শুরু হয়েছে”. Current-period earned profit resets to zero when a new period starts, but historical profit/transactions and actual cash/bank balances remain. On closure, remaining old AED profit cash transfers to AED principal cash as a genuine audited INTERNAL transfer: profit wallet debit, principal wallet credit, total AED cash unchanged. Example principal 1,000 + profit 500 -> principal 1,500 + profit 0, total 1,500. Include choices to record already spent profit, cash held, Bangladesh repatriation (actual AED debit and BDT bank credit at recorded rate), withdrawals and partial settlement; never double-post already recorded spending or remittances. Require reconciliation and explicit confirmation; atomic idempotent closure with rollback. Archive period totals, start/end dates, closing balances and settlements. Keep unpaid agent liabilities carried forward; agent settlement cycle is independent of general accounting period. Do not automatically zero principal cash or cumulative bank deposits.

## 13. Transaction history and reports
Every transaction in separate rounded black-outlined card with type, date/time, amount/currency, rate and profit where applicable. Search, filters, receipt, edit/cancel, audit, account-specific history and allocation-aware filtering. Reports: today/week/month/custom, current and archived periods; separate exchange profit, fee income, own commissions, earned profit, personal expenses by currency, current available cash and bank balance. Do not mix AED/BDT/PKR in one unconverted total; do not conflate period earnings with all-time cash. Transaction calendar and clear analytics if feasible without compromising correctness.

## 14. Security, backups and upgrades
Offline encrypted backup/export and restore; 7-day reminder; first-install restore prompt; integrity checks and round-trip tests including new agent advances, deletion metadata and accounting periods. Optional Google Drive backup only if fully implemented and authorized; otherwise use reminders/manual export. PIN/biometric where supported, no hardcoded secrets. Optional verified GitHub Releases update check, no silent installation. Explain package/signing compatibility. Never ask user to clear app data or uninstall old version before verified backup and migration.

## 15. Architecture and data integrity
Use well-structured Flutter feature modules, SQLite persistence, repository/controller separation, immutable ledger records, double-entry or equally auditable atomic postings, account and transaction identifiers, unique operation keys, accurate foreign keys, incremental migrations and restore validation. All currencies in integer minor units; precise rates. Do not derive cash balances from UI state. Every posting and adjustment must be traceable. Protect against process interruption, app restart, failed migrations, bad backups, and double taps. On startup failure show recoverable diagnostic state; do not wipe DB. Log sanitized exception/stack trace for debugging without exposing sensitive financial rows.

## 16. Mandatory tests
Unit/integration/widget tests for: all Bangladesh and Pakistan rate calculations, rounding reconciliation, funded-on-save, insufficient funds, duplicates, principal/profit separation, bank cumulative deposits, bank adjustments repeated, expenses by wallet, transfers, agent overpayment/advance application/refund, agent cycle closure, period profit transfer, old period archives, cross-account permanent deletion and dependency blocks, deletion preview/backup/rollback, backup/restore, fresh install and upgrade, database reopen, small-screen/text scaling, UI labels and borders, dark mode. Do not weaken tests or suppress errors.

## 17. Implementation and delivery procedure
1. Inspect environment and available repository; confirm new-project destination and package ID without overwriting old app.
2. Plan data schema, posting invariants, migration/import boundaries, UX navigation and tests.
3. Implement complete offline accounting engine and screens.
4. Add four new changes and period-close logic, plus robust backup/security.
5. Run `dart format lib test`, `flutter analyze`, `flutter test`, `flutter build apk --debug`; fix errors. Also test Android startup in an emulator/device when available.
6. Configure GitHub Actions CI for analyze/test/debug APK artifact; keep signing keys secret. Publish verified artifact only when successful.
7. Commit and push to the authorized NEW repository/branch; do not merge or overwrite older repository unless user explicitly asks.
8. Report actual Flutter version, tests run/passed/failed, build status, repository, commit SHA, workflow URL, exact artifact/download link, signing and package ID, backup import compatibility, and any remaining blockers.

If environment or Codex usage limits interrupt work, commit safe verified checkpoints, preserve uncommitted diffs, and produce a detailed handoff. Do not claim unverified features, tests or APK are complete. Build a REAL working app, not just a specification.
