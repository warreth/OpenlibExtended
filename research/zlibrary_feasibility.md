# Z-Library Mirror Feasibility — Empirical Probe (no app code)

**Date:** 2026-09-01 · **Network:** this dev box (NAT egress 213.219.166.233)
**Method:** curl with a realistic Chrome UA, manual redirect following, http vs https, plus a *headless reimplementation* of the DiamWall JS proof-of-work (SHA1-PoW, `c_token`/`c_time` cookies) to test what lies behind the challenge.

## TL;DR

- **None of the mirrors are Cloudflare.** The "PROTECTED" status on open-slum.org is **DiamWall**, a much weaker JS PoW gate. The classic Cloudflare markers (`Just a moment`, `challenge-platform`, `cf-browser-verification`) do **not** appear; the app's `isChallengePage()` would not even recognize the 503 page.
- The DiamWall 503 challenge is **solvable headlessly in ~0.1 s** (SHA1 brute-force over an embedded seed). After solving, **5 of 8 mirrors serve full anonymous search** (51 book items for "flutter"), book detail pages, and even direct downloads.
- **Z-Library search is feasible headless** — no login, no webview needed — but the current `ZlibraryProvider._parse()` would return **0 books** because the live markup uses `<z-bookcard href=...>` custom elements with `<div slot="title">`, not the `<a href="/book/">` anchors the parser looks for.

## Per-mirror results

All tests: `GET /` and `GET /s/flutter` (+ `?page=2`), UA `Chrome/131 Windows`. "PoW solved" = I computed the SHA1 challenge answer offline and set `c_token`/`c_time` cookies.

| Mirror | Scheme | HTTP chain (plain curl) | Behind challenge | PoW solvable headless? | Search after solve | Book page | Anonymous download |
|---|---|---|---|---|---|---|---|
| z-lib.gd | https | `503` (9.6 KB "Checking your browser…") | DiamWall 503 PoW | **Yes** (97k iter, <0.1 s) | **200, 51 `book-item`s** (`/s/flutter`, `?page=2` both 51) | **200** (110 KB) | **Yes** — 302 → `dln1.ncdn.ec` → 37 MB real PDF (`%PDF-1.3`) |
| z-library.sk | https | `307 → self` **infinite loop** (Location: itself, `Server: openresty`, sets `__diamwall`) | DiamWall v2 tier (513 iframe `/cdn-cgi/mitigation/v2/...`, JS-only) | **No** (v2 needs a real JS engine) | blocked on 443 | blocked | blocked |
| z-library.sk | **http** | `503` PoW page directly | DiamWall 503 PoW | **Yes** | **200, 51 items** | **200** (110 KB) | not re-tested (IP limit hit, see below) |
| 1lib.sk | https | `307 → self` loop | DiamWall v2 (513) | **No** | blocked | blocked | blocked |
| 1lib.sk | **http** | `503` PoW → solve | DiamWall 503 PoW | **Yes** | **200, 51 items** | **200** | `/dl/` → `204 No Content` (IP limit) |
| z-lib.fm | https + http | `307 → self` loop; http `301 → https` | DiamWall v2 (513) | **No** | blocked | blocked | blocked |
| articles.sk | https | `503` (same PoW page) | DiamWall 503 PoW | **Yes** | **200, 51 items** (books; `?ext=ARTICLE` also 200) | `302 → /` (no book detail) | `/dl/` → limit page |
| go-to-library.sk | https + http | `307 → self` loop; http `307 → self` | DiamWall v2 (513) | **No** | blocked | blocked | blocked |
| library-access.sk | https | `503` PoW → solve | DiamWall 503 PoW | Yes | **404 "Page not found"** on `/s/` — it's a landing/portal site, no search path | n/a | n/a |
| z-lib.gl | https | `503` PoW → solve | DiamWall 503 PoW | **Yes** | **200, 51 items** | `302 → /` (no book detail) | `/dl/` → limit page |

Notes on the redirect chains:

- The `307` responses are **not** usable redirects: `Location: https://z-library.sk/` points at the same URL, forever. curl exhausts `--max-redirs`. They exist only to set the `__diamwall` cookie; with that cookie the next response is `513 Verifying your browser | DiamWall` with an iframe (`/.well-known/diamwall/load/html/5s.html`) and `/cdn-cgi/mitigation/v2/chl/chlb.lib` — that library and the iframe both return **"Denied"** to any non-browser fetch (even with plausible `sec-fetch-*` headers). Only the plain-http variant of those hosts skips v2 and serves the simple 503 PoW instead.
- The 503 PoW is one round trip: page embeds a 40-hex-char seed, client brute-forces `i` such that `SHA1(seed+i)` has byte `0xB0` at index `n1` (first seed char) and `0x0B` at `n1+1`, then sets `c_token=seed+i`, `c_time=<elapsed>`, reloads. Deterministic: same seed ⇒ same `i` (97584 for every mirror this session — it's a static seed rotating rarely). Cookies survived at least 15 minutes and many requests.

## What "works without login" — precisely

1. **Search:** yes. `/s/<query>` returns the full results page (51 items/page, pagination `?page=N` works) with title, author, year, extension, size, rating, cover URL — all inside `z-bookcard` attributes/slots. No login wall.
2. **Book detail:** yes on z-lib.gd / z-library.sk (http) / 1lib.sk (http). Redirects to `/` on z-lib.gl and articles.sk (different sub-database; their book IDs don't even match gd's).
3. **Download:** yes, but **rate-limited to 5 per IP per 24 h for anonymous users**, and the counter is **family-wide** (hitting it on one mirror exhausts all of them — the error page names the shared egress IP). The flow is `GET /dl/<token>` → `302` to a signed `dln1.ncdn.ec` URL (expires in minutes) → file bytes. After the quota: HTTP 200 HTML "There are more than 5 downloads from your IP … Please sign in" or `204`.
4. **Books a user reads/downloads are limited; reading search results is not.**

## Fit with the app's existing challenge machinery

- `WebviewChallengeSolver.isChallengePage()` checks for DDoS-Guard/Cloudflare markers (`ddos-guard`, `just a moment`, `challenge-platform`, `cf-turnstile`, …). The DiamWall 503 page's title is **"Checking your browser …"** — `checking your browser` IS in the titleMarkers list, so it *would* be detected as a challenge. Good.
- But the app's only solving mechanisms are: (a) cookie replay (never used — comment says it doesn't work for DDoS-Guard) and (b) a **webview** (`HeadlessInAppWebView` / `desktop_webview_window`) that renders the JS and captures the HTML. A webview would clear the 503 PoW automatically (it's plain JS) and would also clear the v2/513 tier that curl cannot. So the **existing pattern fully applies** to Z-Library — arguably better than to Anna's Archive, since the DiamWall 503 tier could even be cleared **without a webview**:
  - Headless option: a pure-Dart SHA1 loop (same one-liner brute force) over the seed scraped from the 503 body, ~100k hashes ≈ 50–100 ms on a phone, then set `c_token`/`c_time` via a `CookieManager`-backed Dio interceptor. No webview, no GUI. (I verified the exact algorithm; it is stable across all 503-tier mirrors and across hosts.)
  - The v2/513 tier (https on .sk/.fm mirrors) is browser-only — a webview clears it, curl-class clients can't.

## Parser mismatch (the real blocker today)

Live search markup (all working mirrors, identical):

```html
<div class="book-item resItemBoxBooks">
  <div class="counter">1</div>
  <z-bookcard id="87453821" href="/book/4XNVZObxX9/….html" download="/dl/B39RQ6kmwG"
              extension="pdf" filesize="35.71 MB" year="" language="English" rating="2.0" …>
    <img data-src="https://…cdn-zlib.sk/covers100/….jpg"/>
    <div slot="title">Flutter-Interview-Questions-and-Answers</div>
    <div slot="author">…</div>
```

`ZlibraryProvider._parse()` looks for `a[href*="/book/"]` inside the item — **there are zero `<a>` tags** in result items, so even a perfectly fetched 200 page yields `books.isEmpty == true` and the provider silently returns `[]`. Author extraction via `a[href*="authorsName"]` also matches nothing (0 occurrences page-wide). Fixing the provider means reading `z-bookcard` attributes (`href`, `download`, `extension`, `filesize`, `year`, `language`) and the `slot="title"`/`slot="author"` divs — trivial in html, ~15 lines.

Also note `bsrv` cookie changes between requests and `Set-Cookie: c_time=null; Expires=1970` arrives on `/dl/` responses — a Dio `CookieManager` handles all of this transparently.

## Recommendation: **(b) disable by default until the provider actually works — then re-enable headless**

One sentence: search is genuinely available without login on 5 of 8 mirrors (z-lib.gd, z-lib.gl, articles.sk over https; z-library.sk, 1lib.sk over http) behind a trivially-solvable DiamWall PoW, but the provider as shipped is dead code — its parser matches zero elements of the real markup and its plain-Dio fetch can never clear even the 503 tier — so it should stay disabled-by-default (which it already is, per its doc comment) until the parser and the PoW cookie bootstrap are added, at which point it becomes feasible **headless** (no webview needed for search; webview only as a fallback for the v2/513 tier on .sk/.fm mirrors).

Concrete follow-ups, in order of leverage:

1. Fix `_parse()` for `z-bookcard` markup (search works today, headless, anonymous).
2. Add a DiamWall 503 solver: on 503, extract seed from body, brute-force SHA1 in Dart, set `c_token`/`c_time` (Dio `CookieManager`), retry once. ~30 lines. Also add `title: "Checking your browser"` already matches `isChallengePage`, so the warmup/solver-page fallback keeps working as designed.
3. Prefer `z-lib.gd` first in the mirror list (only mirror with working anonymous book pages + downloads over https); treat `z-library.sk`/`1lib.sk` as http-only fallbacks; drop `z-lib.fm` (v2-only) from the default list.
4. Downloads: keep them but surface the "5 per 24 h per IP" anonymous limit in UI — or leave downloading to the existing Anna's Archive flow, which has no such limit.

## Raw evidence pointers

- Challenge page (503, seed + PoW loop): saved during session at `/tmp/dw_z-lib_gd_https.jar.body`, `/tmp/zlib_sk_http.html`
- Solved search result (200, 51 items): `/tmp/dw_z-lib_gd_https.jar.body2`, `/tmp/zsk2_ok.html` (z-library.sk http), `/tmp/h_1lib_sk.html` (1lib.sk http)
- Book detail 200: `/tmp/book.html` · Downloaded PDF: `/tmp/dl6.out` (37 MB, `%PDF-1.3`)
- Download-limit page: `/tmp/b2.out` ("more than 5 downloads from your IP … 213.219.166.233")
- PoW solver used for probing: `/tmp/diamwall/solve.py` (research-only, not part of the app)

## Update (2026-09-01, after headless implementation)

Implemented in the app: `lib/services/diamwall_solver.dart` + reworked `ZlibraryProvider`. Verified live: **51 books for "flutter" from z-lib.gd, fully headless, ~1.0 s end-to-end** (challenge solve + cookie retry + parse).

New facts learned while porting to Dart:

1. **The seed embeds in UPPERCASE hex** (`'41422B67...'`), and the marker `'c_token='` sits in the same obfuscated array literal — a single regex `'([0-9a-fA-F]{40})'\s*,\s*'c_token='` finds both reliably (the seed is always the array's first element).
2. **Dio's default `validateStatus` throws on 503** and discards the challenge body — the naive fetch-then-inspect flow never sees the PoW page. The provider must pass `Options(validateStatus: (_) => true)` to read the 503 body. This was the second real blocker after the parser (curl hides this because `-s` shows bodies regardless).
3. The 503 response carries `Cache-Control: no-store` — no cookie jar needed beyond passing `Cookie: c_token=...; c_time=...` on the retry request. `c_time` is just elapsed-seconds; any plausible float works.
4. Solve cost in pure Dart (package:crypto SHA1): **9,783 iterations ≈ 50 ms** on this box, same nonce as the Python probe (97584 earlier in the session — the seed rotated once between probes; the algorithm is unchanged, `n1 = int(seed[0], 16)`).
5. `z-bookcard` attributes worth reading beyond title/author: `img[data-src]` gives working cover thumbnails (cdn-zlib.sk), and `extension`/`filesize`/`year`/`language`/`publisher` attributes fill the `info` line. The book href's id segment (`/book/4XNVZObxX9/...`) is the stable unique id — there is no md5 anywhere on the search page.
6. Fixtures committed for regression tests: `test/fixtures/diamwall_challenge.html` (live 503 page) and `test/fixtures/zlib_search_results.html` (live solved 200 page, 51 cards).
