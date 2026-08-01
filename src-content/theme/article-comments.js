(function () {
    "use strict";

    function prepareCreateLink(container) {
        const link = container.querySelector(".article-comment-create");
        if (!link) return;

        const url = new URL(link.href);
        url.searchParams.set("article_url", window.location.href);
        link.href = url.toString();
    }

    // User-visible strings come from the page, which resolves them per language
    // through the interface term cascade. The script carries no wording of its own.
    function term(container, key) {
        return container.dataset[key] || "";
    }

    function renderIssues(container, issues) {
        const list = container.querySelector(".article-comments-list");
        const status = container.querySelector(".article-comments-status");
        list.replaceChildren();

        if (issues.length === 0) {
            status.textContent = term(container, "i18nEmpty");
            return;
        }

        issues.forEach(function (issue) {
            const item = document.createElement("li");
            const link = document.createElement("a");
            link.href = issue.html_url;
            link.textContent = issue.title;
            link.target = "_blank";
            link.rel = "noopener noreferrer";
            item.appendChild(link);
            list.appendChild(item);
        });
        status.textContent = issues.length === 1
            ? term(container, "i18nCountOne")
            : term(container, "i18nCountMany").replace("%count%", issues.length);
    }

    async function loadIssues(container, button) {
        const repository = container.dataset.repository;
        const articleId = container.dataset.articleId;
        const status = container.querySelector(".article-comments-status");
        const perPage = 100;
        const searchLimit = 1000;
        const query = "repo:" + repository + " is:issue label:\"Artikelkommentar\" label:\"" + articleId + "\"";
        const endpoint = "https://api.github.com/search/issues?q=" + encodeURIComponent(query) +
            "&sort=created&order=desc&per_page=" + perPage;

        button.disabled = true;
        status.textContent = term(container, "i18nLoading");

        try {
            const issues = [];
            let page = 1;
            let resultCount = 0;

            do {
                const response = await fetch(endpoint + "&page=" + page, {
                    headers: { Accept: "application/vnd.github+json" }
                });
                if (!response.ok) throw new Error("GitHub API returned " + response.status);

                const result = await response.json();
                if (result.incomplete_results) throw new Error("GitHub search returned incomplete results");
                if (result.total_count > searchLimit) throw new Error("GitHub search result limit exceeded");
                resultCount = Math.min(result.total_count, searchLimit);
                issues.push.apply(issues, result.items);
                page += 1;
            } while (issues.length < resultCount);

            const matchingIssues = issues.filter(function (issue) {
                const labels = issue.labels.map(function (label) {
                    return typeof label === "string" ? label : label.name;
                });
                return !issue.pull_request && labels.indexOf("Artikelkommentar") !== -1 && labels.indexOf(articleId) !== -1;
            });
            renderIssues(container, matchingIssues);
            button.hidden = true;
        } catch (error) {
            status.textContent = term(container, "i18nError");
            button.disabled = false;
        }
    }

    document.querySelectorAll("[data-article-comments]").forEach(function (container) {
        prepareCreateLink(container);
        const button = container.querySelector(".article-comments-load");
        if (button) button.addEventListener("click", function () { return loadIssues(container, button); });
    });
})();
