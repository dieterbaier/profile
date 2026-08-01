# Interface Terms

`ui-<lang>.adoc` holds the user-visible interface wording per language: menu
labels, the table-of-contents title, footer text, and the status messages the
article-comments script renders.

## How resolution works

`includes/docheader.adoc` includes `ui-de.adoc` first and then, for any other
page language, `ui-<lang>.adoc`. Later attribute assignments win in AsciiDoc, so
the default language acts as the fallback without any file-existence check —
something AsciiDoc cannot express on its own.

Robustness comes from that cascade, completeness from validation: unlike a
content reference, a menu label has nowhere to tell the reader that it is showing
another language, so `validateProfileMetamodel` fails the build when a language
in use is missing a key.

## Hard formatting rule

**These files may contain nothing but attribute entries — no comments, no blank
lines.**

They are included into the AsciiDoc *document header*. A blank line ends the
header, and a comment line inside a header include ends it too. Everything after
that point stops being a header attribute, which silently disables
`:stylesheet:`, `:copycss:`, and `:docinfo:` — the site then renders with the
default Asciidoctor stylesheet instead of its own. The failure looks like a
broken theme, not like a broken include, so the validator rejects any line that
is not an attribute entry.

Document a group of keys here in this file instead of commenting the terms file.

## Page references

`generated/i18n/links-<lang>.adoc` is written by `generateProfileArtifacts` and
included by `docheader.adoc` right after the interface terms. It defines three
attributes per site page:

| Attribute | Meaning |
|---|---|
| `{url_<page>}` | Path to the page, prefixed with `{basedir}` |
| `{url_<page>_lang}` | Language the reference resolved to |
| `{url_<page>_marker}` | Empty, or ` (de)` when the reference fell back |

Keys are derived from the output path, so every page under `site/` and `cv/` is
linkable without a hand-maintained mapping: `articles/articles.html` becomes
`{url_articles_articles}`. Chrome and content must use these attributes instead
of hard-coded paths; the validator rejects a reference no page can satisfy.

Values are relative to `{basedir}`, which every page already sets to the site
root. That keeps the registry independent of page depth and preserves the
relative paths the local and PDF builds rely on — root-relative URLs would have
broken both.

Unlike interface terms, page references **do** fall back: a link leading to a
German page is still usable, so it resolves to the default language and says so.
A German paragraph inside an English page is not, which is why fragments follow
the opposite rule.

The same formatting constraint applies to the generated registry, and it is
guarded by a test: `:name:value` without the space after the colon is not an
attribute entry and would end the header just like a blank line.

## Content fragments

`<lang>/` holds the reusable content fragments: profile prose, contact data,
languages, education, professional experience, projects and skills. Pages include
them language-parameterized:

```asciidoc
include::{includesdir}/i18n/{lang}/profile/profile.adoc[]
```

**Fragments do not fall back.** A page may only include fragments of its own
language; a missing translation fails the build, naming the page, the fragment
and the language. A link leading to a German page is still usable, so it falls
back and says so — a German paragraph inside an English page is not, so the
build stops instead of producing a page in mixed languages.

The validator walks the include tree of every page, carrying attributes along the
way so attribute-driven includes such as `{pe-description-file}` resolve. It does
not evaluate `ifdef`/`ifeval` and walks every branch, which can ask for more
translations than a single build needs but never fewer.

Fragments that are not translated yet are reported as a coverage warning. They
only become an error once a page in that language includes one, so translation
can progress fragment by fragment — but a *page* is all-or-nothing: every
fragment it pulls in has to exist in its language before it can be published.

## Adding a language

1. Copy `ui-de.adoc` to `ui-<lang>.adoc` and translate every value.
2. Keep the key set identical; the validator reports missing and unknown keys.
3. `%count%` in `ui_comments_count_many` is a placeholder the browser fills in.
   It is deliberately not an AsciiDoc attribute reference, so it survives
   attribute substitution untouched.
