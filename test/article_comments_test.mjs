import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import vm from 'node:vm';

const script = await readFile(new URL('../src-content/theme/article-comments.js', import.meta.url), 'utf8');

class Element {
    constructor(kind = 'div') {
        this.kind = kind;
        this.children = [];
        this.dataset = {};
        this.disabled = false;
        this.hidden = false;
        this.textContent = '';
    }

    addEventListener(_event, listener) {
        this.listener = listener;
    }

    appendChild(child) {
        this.children.push(child);
    }

    replaceChildren() {
        this.children = [];
    }
}

function articleComments(fetch) {
    const button = new Element('button');
    const status = new Element('p');
    const list = new Element('ul');
    const createLink = new Element('a');
    createLink.href = 'https://github.com/dieterbaier/profile-artikelkommentare/issues/new?template=artikelkommentar.yml';
    const elements = {
        '.article-comment-create': createLink,
        '.article-comments-load': button,
        '.article-comments-status': status,
        '.article-comments-list': list
    };
    const container = new Element('section');
    // The page supplies every user-visible string, resolved per language through
    // the interface term cascade; the script carries no wording of its own.
    container.dataset = {
        repository: 'dieterbaier/profile-artikelkommentare',
        articleId: 'ART-101-example',
        i18nEmpty: 'Noch keine Kommentare vorhanden.',
        i18nLoading: 'Kommentare werden von GitHub geladen …',
        i18nError: 'Kommentare konnten derzeit nicht geladen werden. Bitte versuchen Sie es später erneut.',
        i18nCountOne: 'Ein Kommentar:',
        i18nCountMany: '%count% Kommentare:'
    };
    container.querySelector = selector => elements[selector];

    const document = {
        createElement: kind => new Element(kind),
        querySelectorAll: () => [container]
    };
    const window = { location: { href: 'http://localhost:63342/articles/example.html' } };
    vm.runInNewContext(script, { document, fetch, URL, window });

    return { button, container, createLink, list, status };
}

test('existing comments use server-side search pagination and render matching issues', async () => {
    // Given: two result pages containing exact matches and a defensive mismatch
    const requests = [];
    const pages = [
        {
            total_count: 101,
            incomplete_results: false,
            items: Array.from({ length: 100 }, (_, index) => ({
                title: `Frei editierbarer Kommentar ${index + 1}`,
                html_url: `https://github.com/dieterbaier/profile-artikelkommentare/issues/${index + 1}`,
                labels: [{ name: 'Artikelkommentar' }, { name: 'ART-101-example' }]
            }))
        },
        {
            total_count: 101,
            incomplete_results: false,
            items: [
                {
                    title: 'Vollständig geänderter Titel',
                    html_url: 'https://github.com/dieterbaier/profile-artikelkommentare/issues/101',
                    labels: ['Artikelkommentar', 'ART-101-example']
                },
                {
                    title: 'Defensiv ausgefilterter Treffer',
                    html_url: 'https://github.com/dieterbaier/profile-artikelkommentare/issues/102',
                    labels: [{ name: 'Artikelkommentar' }, { name: 'ART-OTHER' }]
                }
            ]
        }
    ];
    const fetch = async url => {
        requests.push(url);
        return { ok: true, json: async () => pages[requests.length - 1] };
    };
    const { button, createLink, list, status } = articleComments(fetch);

    // When: the reader explicitly loads existing comments
    await button.listener();

    // Then: the form receives the current page URL, GitHub narrows by both
    // stable labels, all pages are read, and only exact label matches render
    assert.equal(new URL(createLink.href).searchParams.get('article_url'), 'http://localhost:63342/articles/example.html');
    assert.equal(requests.length, 2);
    assert.match(requests[0], /^https:\/\/api\.github\.com\/search\/issues\?/);
    assert.match(decodeURIComponent(requests[0]), /repo:dieterbaier\/profile-artikelkommentare is:issue label:"Artikelkommentar" label:"ART-101-example"/);
    assert.match(requests[0], /page=1$/);
    assert.match(requests[1], /page=2$/);
    assert.equal(list.children.length, 101);
    assert.equal(list.children[100].children[0].textContent, 'Vollständig geänderter Titel');
    assert.equal(status.textContent, '101 Kommentare:');
    assert.equal(button.hidden, true);
});

test('searches beyond the GitHub result limit remain retryable', async () => {
    // Given: more comments exist than GitHub Search can return
    const fetch = async () => ({
        ok: true,
        json: async () => ({ total_count: 1001, incomplete_results: false, items: [] })
    });
    const { button, status } = articleComments(fetch);

    // When: the reader loads comments
    await button.listener();

    // Then: the optional interaction reports failure without disabling retry
    assert.equal(status.textContent, 'Kommentare konnten derzeit nicht geladen werden. Bitte versuchen Sie es später erneut.');
    assert.equal(button.disabled, false);
    assert.equal(button.hidden, false);
});

test('comment wording follows the page language', async () => {
    // Given: a page that supplies English interface terms
    const fetch = async () => ({
        ok: true,
        json: async () => ({ total_count: 0, incomplete_results: false, items: [] })
    });
    const { button, status, container } = articleComments(fetch);
    container.dataset.i18nEmpty = 'No comments yet.';

    // When: the reader loads comments and none exist
    await button.listener();

    // Then: the script renders the page's wording, not a built-in German string
    assert.equal(status.textContent, 'No comments yet.');
});
