# Demo script for Monday 26 October

A ten-minute walk-through of the scratch build for Liz. The aim is not to sell the tool. It is to show what one afternoon produced, where the evidence is strong, where it is absent, and to get four decisions.

## Before the meeting

Have these open in tabs, in this order, before she sits down:

1. The one-pager written for her (`~/Documents/gitrepos/cb-laz/arti-vault/drafts/2026-10-23-aqua-for-all-one-pager/`, the rendered PDF). She has read it; it is the anchor.
2. `docs/evidence-review.html`, scrolled to section 3 (the flow diagram).
3. The app, already running. In a terminal at the repository root:

   ```sh
   /usr/local/bin/Rscript -e 'washhealth::run_app(port = 4000, launch.browser = TRUE)'
   ```

   Leave that terminal alone; stop it with Ctrl-C after the meeting. If the app will not start, the fallback is `docs/worked-examples.html`, which shows the same two cases with the ledger.
4. `docs/reports/2026-10-23-ilf-kwsh-2025-transaction-report.html` (the rendered KWSH report; if the folder is empty, render it with the R snippet below).

An R console with the package loaded, in case a question needs a number the app does not show:

```r
library(washhealth)
tx <- example_transactions()
res <- estimate_transaction(tx[tx$enterprise == "KWSH", ])
res$results
res$ledger
factors_version()
render_transaction_report(tx[tx$enterprise == "KWSH", ], output_dir = "docs/reports")
```

Nothing in the meeting needs the network.

## The walk-through (10 minutes)

### 0:00 The one-pager (1 minute)

Say: your verdict stood. The three evidence questions are a research programme. The afternoon tested that against the literature and the test confirmed it: the evidence answers the first question well for a short list, the second question partly, the third coarsely. What exists now is a tool that is honest about exactly that.

### 1:00 The evidence review: the flow and the table (2.5 minutes)

Tab 2. Point at the flow diagram: 10 577 records in, 248 included, 123 mapped, 144 full texts, 77 effect sizes extracted, 24 carried by the tool. Every number in the diagram is computed from the screening log when the page renders.

Scroll to section 5, the table of the 24 factor rows. Point at the certainty column: moderate for filtration, chlorination, solar disinfection, handwashing promotion and basic sanitation; very low for water supply and sewerage; low for the mortality band and STH. Then the sentence under the table: no pooled estimate exists for safely managed on-site sanitation or faecal sludge management services, and WHO says so.

Do not scroll further. The limitations section is for her to read later; mention only that one screener did everything in one pass.

### 3:30 The app: KWSH, then Aqua Clara (3 minutes)

Tab 3, the *Ex-post (reporting)* tab. Enter the KWSH case as the ILF report gives it:

- Country: Cambodia
- Output type: new piped household connection
- Verified quantity: 2500
- Setting: rural
- Reporting period: 2025-01-01 to 2025-12-31
- Verified use rate: 1 (the connections are assumed active), "Use was verified" ticked
- Baseline water source: not known (assumed unimproved, flagged)
- Incentive-attributable share: 0.5, ticked (illustrative)
- Verified by: any name; verification date: any date

Press *Estimate from verified outputs*. Read out: 10 250 people reached; 272 diarrhoea cases averted in children under five, range 0 to 519; label **very low**. Show the reasons list: the water supply effect is rated very low in the source review, its interval includes no effect (so the low estimate is zero), the baseline source was assumed, and the trials used caregiver-reported diarrhoea.

Now Aqua Clara Kenya. Change: Country Kenya; output type household water filter; quantity 1000 (illustrative, the report gives hubs and pupils); use rate 0.93 (the share washing the filter weekly, from the report); baseline source unimproved. Press the button. Read out: 3 700 people; 681 cases averted, range 545 to 803; label **moderate**. Same tool, same arithmetic, different evidence.

### 6:30 The ledger and the report (1.5 minutes)

Scroll down in the app to *Factor rows used*. Say: this is the whole calculation. Twelve rows, each with a table, a row id, a value and a citation. Nothing else enters. A reviewer checks a number by opening the source at the locator.

Tab 4, the KWSH report. Scroll once through: inputs as verified, factor rows, estimated outcomes with ranges and label, the additionality paragraph, the communication rules at the end, and the two version stamps. Say: this is what a funder would receive; no single number leaves without its range and its label.

### 8:00 The three points and the questions (2 minutes)

The three points to make, in one sentence each:

1. **Where the evidence is strong.** Diarrhoea in children under five for point-of-use treatment and handwashing promotion, with moderate certainty from pooled randomised trials; that short list can carry a conversion factor with an interval.
2. **Where it is absent.** Faecal sludge management, water kiosks, safely managed on-site sanitation, institutional connections, in-line chlorination as a service, and any move between two improved water sources. The tool reports reach and says "no estimate" rather than borrowing a factor without a flag.
3. **What the confidence label does.** It starts at the certainty of the evidence and drops one step for every missing input: use not verified, baseline source assumed, a regional substitute, an evidence gap. It stops a very low estimate from looking like a moderate one, which is the main protection an outcome funder needs.

Then the four questions, written down so that each gets an answer:

1. **Publish or keep private?** CC BY 4.0 for the tables and documents, MIT for the code; nothing published until she says so.
2. **Whose name goes on it?** Lars alone, Lars with the GHE affiliation, or the group; and whether ETH or GHE is named in the README and in any email at all.
3. **Who reviews the factor rows?** The governance document needs a second person with water, sanitation and health evidence experience for every curated row (24 effect rows, 20 adjustment rows, 13 pathway rows) and a sample of the 1 626 abstract decisions. A name, or a decision that this waits.
4. **Write to Aqua for All and Rick Johnston, or not?** The drafts are in `docs/draft-email-aqua-for-all.md`: no proposal, what was built and why, an offer to be involved in the tool development phase with whichever team they select. Send, change, or drop.

If there is time: the repository home (an openwashdata or a Global-Health-Engineering organisation; the trade-off is in `docs/publication-checklist.md`), and whether the pkgdown site should go up with the repository.

## What not to say

- Do not call any number a finding. Every health number is an estimate from unreviewed tables.
- Do not claim ETH or GHE endorsement of anything.
- Do not promise Aqua for All anything before question 4 is answered.
