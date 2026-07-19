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
    const elements = {
        '.article-comments-load': button,
        '.article-comments-status': status,
        '.article-comments-list': list
    };
    const container = new Element('section');
    container.dataset = {
        repository: 'dieterbaier/profile',
        issueMarker: '[Artikelkommentar][ART-101-example]'
    };
    container.querySelector = selector => elements[selector];

    const document = {
        createElement: kind => new Element(kind),
        querySelectorAll: () => [container]
    };
    vm.runInNewContext(script, { document, fetch });

    return { button, list, status };
}

test('existing comments use server-side search pagination and render matching issues', async () => {
    // Given: two result pages containing exact matches and a defensive mismatch
    const requests = [];
    const pages = [
        {
            total_count: 101,
            incomplete_results: false,
            items: Array.from({ length: 100 }, (_, index) => ({
                title: `[Artikelkommentar][ART-101-example] Kommentar ${index + 1}`,
                html_url: `https://github.com/dieterbaier/profile/issues/${index + 1}`
            }))
        },
        {
            total_count: 101,
            incomplete_results: false,
            items: [
                {
                    title: '[Artikelkommentar][ART-101-example] Kommentar 101',
                    html_url: 'https://github.com/dieterbaier/profile/issues/101'
                },
                {
                    title: '[Artikelkommentar][ART-OTHER] Kein Treffer',
                    html_url: 'https://github.com/dieterbaier/profile/issues/102'
                }
            ]
        }
    ];
    const fetch = async url => {
        requests.push(url);
        return { ok: true, json: async () => pages[requests.length - 1] };
    };
    const { button, list, status } = articleComments(fetch);

    // When: the reader explicitly loads existing comments
    await button.listener();

    // Then: GitHub narrows by repository and title marker, all pages are read,
    // and only exact marker matches are rendered safely as links
    assert.equal(requests.length, 2);
    assert.match(requests[0], /^https:\/\/api\.github\.com\/search\/issues\?/);
    assert.match(decodeURIComponent(requests[0]), /repo:dieterbaier\/profile in:title "\[Artikelkommentar\]\[ART-101-example\]"/);
    assert.match(requests[0], /page=1$/);
    assert.match(requests[1], /page=2$/);
    assert.equal(list.children.length, 101);
    assert.equal(list.children[100].children[0].textContent, '[Artikelkommentar][ART-101-example] Kommentar 101');
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
