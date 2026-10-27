# AuriUI v1 — grammar specification

AuriUI is a line-oriented document format for interactive native SwiftUI.
Apps can author documents directly or render them as a model streams output.
The format supports screens, navigation actions, and local state.

`Contract/auriui-v1.json` is the executable source of truth for component
identifiers, syntax samples, prompt grammar, validator keywords, and client
compatibility gates. This file is normative for the format's behavior and
design rules. Change the manifest and this document together, then run
`node Scripts/generate-contract.mjs` from the package directory.
The generation check and Swift parser parity tests reject drift.

## Design invariants

1. **One line = one renderable node.** A line is parseable the moment its
   newline arrives; the client renders it immediately. No construct spans lines
   except containers collecting subsequent `item` lines.
2. **Lossy by line.** A malformed line is dropped individually; the document
   survives. A container that ends up with zero valid items is dropped. A
   document with zero valid sections is invalid (caller falls back).
3. **The model never does arithmetic.** Prices ride on items (`price:`); the
   client computes and formats every total (`{total}`). Copying a number is
   allowed; summing is not.
4. **Forward compatible.** Unknown `key:value` pairs are ignored. Unknown line
   keywords drop only that line. The `aui <version>` header gates breaking
   changes.
5. **Forms execute registered capabilities only.** A form names one available
   capability, validates locally, asks for confirmation, and submits through a
   matching action. AuriUI v1 has no password, payment, booking, health, or
   other sensitive field type.
6. **Charts preserve the supplied data.** A chart has one explicit unit, a
   bounded number of points, and a complete value for every X/series pair.
   The client computes scales and fallbacks; the model never fills gaps.

## Lexical rules

- A document is UTF-8 text, one statement per line. Blank lines are ignored.
  Lines starting with `#` are comments (tolerated, never emitted by prompts).
- Tokens on a line, in order: **keyword**, then positional values, then
  `key:value` pairs, then at most one **action** (`@kind(...)`) at the end.
- **Quoted string**: `"..."` with `\"` and `\\` escapes. Newlines never appear
  inside strings.
- **Bare token**: a run without whitespace (`check`, `multi`, `brioche`, `2.50`).
- **Emoji**: a bare token whose first character is emoji fills a line's
  optional visual slot, wherever it appears before the first quoted string.
- **key:value**: value is a bare token or quoted string (`price:2.50`,
  `img:"smash burger close-up"`).
- **Action**: `@send("message")`, `@nav("next-screen description")`,
  `@url(https://example.com)`. One per line, last token.
- Markdown (`**bold**`, `*italic*`) is honored only in `intro` text, `bullets`
  item text, and `expand` item bodies. Plain text everywhere else.

## Document header

```
aui 1
```

Optional first content line; blank lines and comments may precede it. Without
a header, the parser assumes version 1. A malformed header, unsupported
version, duplicate header, or header after content rejects the whole document.
`AuriUIStreamingParser.failure` explains the rejection; `document` becomes
empty and the parser ignores subsequent input. Create a new parser for a new
document. Other malformed lines still drop individually.

A document that contains a
`screen` line is a **screen** (full-screen surface); otherwise it is an
**answer** (sections rendered inline in chat).

## Answer documents

A document without a `screen` line is an inline chat answer. It should open
with a `summary "…"` line — 1–3 plain-text sentences that stand alone as a
complete answer. The client shows this decision-first lede above the generated
sections, speaks it in voice mode, and stores it as the message text. It is not
duplicated in `sections`. Follow it with 4–12 sections ending with `chips`.

## Screen lines

```
screen customize_burger "Customize burger" "Classic Smash · $12.50" tint:amber
state base:12.50 cur:USD
```

- `screen <snake_id> "Title" "Subtitle"? tint:<name>?` — must precede all
  sections. `tint` is the flow's art direction: one accent name (amber,
  orange, mint, teal, blue, indigo, violet, rose, red, green, slate) chosen
  to match the domain's mood and kept consistent across a flow's screens.
- `state` — money context: `base:` (number, default 0) and `cur:` (ISO 4217,
  default USD). Emit only when the screen has priced items.

## Sections

**Leaf lines** (complete in one line):

| Line | Meaning |
|---|---|
| `intro "text"` | Lede paragraph (markdown ok) |
| `header 🍪 "Title" "Subtitle"?` | Section heading with emoji art |
| `hero img:"query" "Caption"?` | Full-bleed image header |
| `button "Label" @action` / `button primary "Label" @action` | Standalone CTA |

**Container lines** open a section; their matching child lines attach until a
different keyword begins the next section:

| Line | Items are |
|---|---|
| `row "Title"?` | Horizontal media tiles: `item 🎬 "Title" "Subtitle"? img:"query" cap:"2024 · 8.5★"? badge:"New"? @action?` |
| `posters "Title"?` | 2:3 cover-art carousel (films, shows, books, albums) — same item shape as `row`; `img` should be the actual poster/cover |
| `menu "Title"?` | Commerce rows: `item 🍔 "Classic Smash" "Double patty, secret sauce" price:12.50 img:"query" badge:"Bestseller"? @action?` |
| `grid "Title"?` | Compact tiles, same item shape as `row` |
| `cards` | 1–2 entity cards: `item 🚗 "Title" "Positioning" img:"query" s:"Range=333 mi" s:"0–60=4.2 s" @action?` (repeat `s:"Label=Value"` ≤ 3) |
| `steps "Title"?` | Ordered steps: `item 🔥 "Short title" "One-sentence detail"` |
| `facts "Title"?` | Icon-led feature rows: `item 🔌 "Road trip easy" "Supercharger access keeps charging simple."` — for a product's or place's qualities |
| `bullets "Title"? check?` | Bullets (`check` = checklist style): `item "text"` |
| `stats "Title"?` | Stat tiles: `item "8.5" "IMDb" trend:up?` (value ≤ 8 chars) |
| `expand "Title"?` | Expandables: `item "Question" "Body"` |
| `chips` | Follow-ups: `item "Label ≤ 4 words" "Full prompt sent on tap"?` (prompt defaults to label) |
| `sources` | Citations: `item "Title" url:"https://…"` |
| `list "Title"? pick:<group>` | Single-select options: `item 🥐 "Brioche" "Buttery, toasted" val:brioche price:0 sel?` |
| `list "Title"? multi` | Toggleable add-ons, same item shape |
| `receipt "Title"?` | Order lines: `item "1× Classic Smash" price:14.50` — client appends a computed Total row |

**Capability-gated charts** show small, grounded numeric datasets as native
line or grouped-bar charts:

```
chart line "Weekly focus" unit:"min"
point "Mon" "Focus" v:42
point "Tue" "Focus" v:55
point "Wed" "Focus" v:61
```

- `chart line|bar "Title" unit:"…"` opens the chart. The unit is required and
  applies to every value.
- A chart has 2–12 distinct ordered X labels, 1–3 series, and at most 36
  points. Each `point "X label" "Series" v:<decimal>` pair must be unique.
- Every series must contain exactly one point for every X label. Missing or
  mixed-shape datasets drop as a block instead of implying false continuity.
- Use `line` only when the X order is meaningful (time, distance, sequence).
  Use grouped `bar` for category comparisons. Stacked bars are not in v1.
- Every value, label, and unit must come from DATA or the user's message. Do
  not estimate missing values or turn a single number into a chart.
- The client keeps bar scales anchored at zero, exposes native chart
  accessibility, and provides an expandable text table from the same points.

**Capability-gated forms** collect a small amount of non-sensitive input for
a real action such as refining a search or drafting the next assistant turn:

```
form refine_search "Refine search" cap:nav confirm:"Search with these details?"
field text query "Search terms" placeholder:"What are you looking for?" required min:2 max:80
field textarea details "More detail" placeholder:"Optional context" max:500
field select timeframe "Time frame" opt:"any=Any time" opt:"week=Past week" val:any
field date after "After" val:2026-07-31
field slider radius "Radius" min:1 max:100 step:1 val:25 unit:"mi"
submit "Show results" @nav("Results for {query}, {timeframe}, after {after}, within {radius}")
```

- `form <snake_id> "Title" cap:nav|send confirm:"…"` opens the form.
  `cap` must name an available capability that accepts form input.
- A form contains 1–6 unique fields and exactly one trailing `submit`.
- `text` and `textarea` accept `placeholder:`, `val:`, `required`, `min:` and
  `max:` character limits. Defaults are 200 and 1,000 characters when `max:`
  is omitted; the hard limit is 2,000.
- `select` takes 2–8 repeated `opt:"value=Label"` pairs. `val:` chooses the
  initial option; otherwise the first option wins.
- `date` requires an ISO `val:YYYY-MM-DD` so the generated default is explicit.
- `slider` requires decimal `min:` and `max:`, with optional `step:`, `val:`,
  and `unit:`. The default value is its minimum.
- `submit "Label" @action` must use the same capability as `cap`. Forms cannot
  submit to `@url`; use a normal button for a service handoff.
- The client keeps values stable while a document streams, validates locally,
  shows inline errors, and requires confirmation before dispatch.

**Neutral tables** — standings, scoreboards, schedules, and compact matrices
that are not a winner/loser comparison:

```
table "League table"
tcol "Team"
tcol "P"
tcol "GD"
tcol "Pts"
trow "Arsenal" "32" "+42" "74" hi
trow "Liverpool" "32" "+40" "71"
```

`table "Title"?` takes 2–4 `tcol "Header"` lines followed by `trow` lines
with one quoted value per column. Missing trailing values render as an em dash;
extras are ignored. The optional `hi` flag highlights a row that is relevant
to the user. Use `table` when the columns are neutral fields; use `compare`
when the interface should call out contender advantages and tradeoffs.

**Comparison block:**

```
compare 🥊
col "M4 Pro" img:"macbook pro m4 pro"
col "M4 Max" img:"macbook pro m4 max"
cgroup "Performance"
crow "CPU cores" "14" "16" win:2 n1:"Fewer cores" n2:"More cores"
crow "Battery" "22 h" "18 h" win:1 n1:"Longer life" n2:"Shorter life"
```

Contenders come from `col` lines (title + optional contender image) and/or
2–3 quoted titles on the `compare` line itself; `col` lines must precede the
rows. `cgroup` (optional) titles a row group; `crow` takes a label plus one
value per column, optional `win:<column#>`, and optional contextual badges
`n1:"…"` / `n2:"…"` / `n3:"…"` aligned to each column. Badges are short
(three words or fewer) and explain the practical edge (for example, "More
space" or "Lower cost") instead of repeating the value. In a two-column row,
`win:` marks the winning cell as positive and the other cell as negative;
omit `win:` when the tradeoff is subjective. Every row compares one metric in
the same units across columns.

**Tabs** (the only explicit block; depth 1, 2–4 tabs):

```
tabs
tab "Weekend"
row "Saturday"
item 🏛 "Louvre" "Book ahead"
tab "Full week"
bullets
item "Day 1–2: the classics"
end
```

**Detail pages** — tap-to-open mini interfaces, emitted **after** all visible
sections so tiles render early and pages generate in the tail:

```
page "Dune: Part Two"
header 🎬 "Dune: Part Two" "2024 · Sci-fi epic"
stats
item "8.5" "IMDb"
item "166 min" "Runtime"
chips
item "Where to stream" "Where can I stream Dune: Part Two?"
```

`page "<title>"` — everything after it (until the next `page` or EOF) belongs
to that page. The title must exactly match a `row`/`posters`/`grid`/`menu`/
`cards` item title or a `compare` column title; non-matching pages are
dropped. Pages never contain `tabs` or `page`. In a comparison, one page per
contender turns each column header into a tap-to-open detail page.

Each page owns its selections, form values, and total. A page's `state`
line overrides its money context without changing the root or other pages;
omitted fields inherit the root context. A page without `state` inherits the
root money context. Closing and reopening a page keeps its live controls.

## Actions and tap defaults

- `@send("…")` — send a message to the assistant (chat turn).
- `@nav("…")` — request the next screen; the argument is a natural-language
  description of that screen (it is also the speculation prompt — write it as
  a complete, self-contained screen brief, embedding the relevant DATA facts
  so grounding propagates down the flow).
- `@url(r3)` | `@url(find:"query")` | `@url(https://…)` — open a link. The
  model never mints URLs: it cites a resource id from the screen's DATA
  block (`r3`), or defers to a tap-time lookup (`find:"dune part two official
  trailer"`). Literal URLs are tolerated by parsers but composers must not
  invent them. The same reference forms are valid in `url:` key positions
  (e.g. `sources` items).
- Form submit actions may use only `@nav` or `@send`, must match the form's
  `cap:`, and are dispatched only when that capability is still available.

The client may also build trusted AuriUI documents in memory with host-only
actions. They have no DSL spelling, never parse from model output, and execute
only when the containing app registers the exact capability identifier.

Defaults when a line has no action: `row`/`grid`/`cards` items open their
matching `page` if one exists; `chips` items send their prompt; `list` items
mutate selection state. Explicit actions override defaults.

## Money and interpolation

- `price:` values are plain decimals in the screen currency. The client
  renders them as tags (`+$2.00`, or `Included` when 0) — do not duplicate
  the price into visible text.
- `{total}` inside any quoted string is replaced by the client with the
  formatted sum: selected `list` prices plus either all `receipt` prices
  (when receipt lines exist — receipts itemize everything, and `state base`
  is ignored to make double-counting impossible) or `state base`. It may appear in labels and in `@nav`/`@send` arguments — actions
  are interpolated before dispatch, so the composer of the next screen
  receives exact numbers as input and must copy them, never compute.
- `{selections}` is replaced with the comma-joined titles of every currently
  selected `list` item (picks first, then toggles), e.g.
  `Brioche, American, Applewood bacon`. Use it in `@nav` arguments so the
  next screen's composer receives the exact configuration.
- In `pick` groups the first item is selected unless another carries `sel`.
- `{field_id}` in a form's submit action is replaced with the locally held
  display value after validation. Select fields use their visible label and
  slider fields include their unit. Unknown placeholders remain unchanged.

## Grounding contract (for composers and orchestrators)

Screens are composed from a DATA block the orchestrator provides (search
results, user memory, structured facts), with resources numbered `r1…rN`.
The composer may only state facts present in DATA; sections whose facts are
missing are omitted, never invented. Every entity name, rating, price, and
URL traces to DATA or to the request brief. Flows are finite: when the
user's task completes, the screen ends with chips, `@send`, or a `@url`
handoff — never an endless chain of speculative screens.

## Sizing rules (for composers)

Phone-first: titles ≤ 4 words, subtitles/captions ≤ 6 words, step details
≤ 20 words, stat values ≤ 8 characters, comparison badges ≤ 3 words, ≤ 4
stats per `stats`, and ≤ 3 `s:` per card. Answers adapt to the requested depth
(4–6 compact, 5–8 standard, 6–10 detailed visible sections); trailing detail
pages do not count toward that range. A single generated screen should be
~300 tokens; 500 is its budget ceiling (enforced by fixture tests).

## Example — complete answer document

```
aui 1
intro "Here's a recipe built for **maximum chew** — soft centers, crisp edges."
header 🍪 "Extra chewy cookies" "Makes 24"
grid "What you need"
item 🧈 "Butter" "1 cup, melted"
item 🟤 "Brown sugar" "1 cup, packed"
item 🌾 "Flour" "2.5 cups"
item 🥚 "Eggs" "2 large"
steps "Bake it step by step"
item 🔥 "Heat the oven" "Preheat to 375°F and line two sheets with parchment."
item 🥣 "Mix the wet" "Whisk melted butter with sugars, then beat in eggs."
item 🧊 "Chill the dough" "Rest 30–60 minutes so the cookies bake thick."
item 🍪 "Bake" "10 minutes, until edges set but centers look underdone."
bullets "Why this works" check
item "**Melted butter** adds chew instead of cakey lift."
item "**Brown sugar's molasses** keeps centers moist."
chips
item "Make it gluten-free" "Adapt this chewy cookie recipe to be gluten-free"
item "Double the batch" "Scale this cookie recipe to 48 cookies"
```

For a complete screen flow, see `Tests/AuriUITests/Fixtures/burger_*.aui` —
the canonical Burger Test transcript.
