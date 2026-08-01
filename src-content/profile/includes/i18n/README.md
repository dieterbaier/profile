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

## Adding a language

1. Copy `ui-de.adoc` to `ui-<lang>.adoc` and translate every value.
2. Keep the key set identical; the validator reports missing and unknown keys.
3. `%count%` in `ui_comments_count_many` is a placeholder the browser fills in.
   It is deliberately not an AsciiDoc attribute reference, so it survives
   attribute substitution untouched.
