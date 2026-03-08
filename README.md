# 📄 Documentation Pipeline

A reproducible documentation pipeline built with **Gradle, Asciidoctor, Pandoc, and Docker**.

This project generates multiple documentation artifacts (HTML, PDF, Markdown) from a single source of truth and is designed to run **locally and in CI with identical results**.

---

## ✨ Features

* 📚 Generate **HTML, PDF, and Markdown** from AsciiDoc
* 🔁 Multi-step pipeline (Asciidoctor → DocBook → Pandoc)
* 🧩 Modular Gradle build (custom tasks, reusable config)
* 🐳 Fully containerized build environment
* ⚙️ Works locally and in GitHub Actions
* 🎯 Deterministic builds (no “works on my machine”)

---

## 🏗️ Architecture Overview

```
AsciiDoc
   │
   ├── Asciidoctor (HTML / PDF)
   │
   └── DocBook → Pandoc → Markdown
```

Additional steps:

* Asset processing (fonts, images, icons)
* Cleanup / housekeeping
* CI/CD deployment

---

## 🚀 Usage

### Local (with container)

```bash
./build.sh buildSite
```

or

```bash
./build.sh buildReadme
```

or

```bash
./build.sh buildCVPersonal
```

---

### Local (without container)

```bash
./gradlew buildSite
```

or

```bash
./gradlew buildReadme
```

or

```bash
./gradlew buildCVPersonal
```

---

## 📦 Outputs

| Target       | Output                     |
| ------------ |----------------------------|
| README       | `build/readme/README.md`   |
| README       | `build/readme/README.html` |
| Website      | `build/site/index.html`    |
| CV (HTML)    | `build/site/cv.html`       |
| CV (PDF)     | `build/site/cv/cv.pdf`     |
| Personal PDF | `build/cv/`                |

---

## 🐳 Docker

The project provides a container image with all prerequisites:

* Java
* Gradle
* Asciidoctor
* Pandoc
* Graphviz

The image is built automatically in CI and reused locally.

---

## ⚙️ Requirements (without Docker)

* Java 17+
* Pandoc
* Graphviz

---

## 🔧 Build System

The build is implemented using Gradle:

* Custom tasks (e.g. Pandoc integration)
* Asset pipeline (Copy tasks)
* Cleanup (Delete tasks)
* Environment checks

---

## 📐 Project Structure

```
src/
  profile/
    cv/
    readme/
    site/
    theme/
    includes/

build/
```

---

## 🧠 Why this project exists

This project started with a simple problem:

Maintaining a personal profile across multiple platforms is painful and error-prone.

* GitHub personal README
* GitLab personal README
* Personal website
* CV as HTML
* CV as PDF
* Tailored CVs for project applications

All of these share the same core information — but differ in format, level of detail, and audience.

---

### 🎯 Goal

> Maintain **one single source of truth** and generate multiple tailored outputs.

---

### 🧩 Approach

* Write everything in **AsciiDoc**
* Use a **build pipeline** to generate:

    * Website
    * Public CV
    * Private CV (with personal data)
    * README files
* Inject environment-specific data (e.g. contact details; check `.env-example` to get an idea what personal information can be injected via the environment; if you rename `.env-example` to `.env` and insert your personal info, `./build.sh buildCVPersonal` will inject these values into the `build/cv/cv.pdf`) only when needed

---

### 🚀 Result

* No duplication
* No inconsistencies
* Fully automated publishing
* Reproducible builds across environments

---

This project is both:

* a **real-world solution for personal branding**
* and a **technical exploration of documentation as code**


---

## 🛣️ Roadmap

* [ ] Link validation
* [ ] Build verification tests
* [ ] Improved theming
* [ ] Multi-tenant site generation

---

## 🌐 Live

- Website: https://dieterbaier.eu
- Architecture: https://dieterbaier.github.io/profile

---

## 📄 License

MIT
