# morehouse.dev

Website and blog posts written by Matt Morehouse. Primary focus is the Bitcoin
Lightning Network.

Built with [Hugo](https://gohugo.io/). The site ships no JavaScript, loads no
webfonts, and makes no third-party requests.

## Local development

```bash
./serve.sh               # http://localhost:1313, live reload
```

## Writing a post

```bash
hugo new content lightning/my-post.md
vim content/lightning/my-post.md
```

Drop the header image in `static/images/`. If it is wider than 1600px:

```bash
magick ~/header.png -resize '1600x>' -strip static/images/my-post.png
oxipng -o max --strip safe static/images/my-post.png
```

Tag pages, the feed, the sitemap, and the `/posts/` archive all update
themselves.

## Front matter

```yaml
---
title: "LND: Infinite Inbox DoS"
description: "One sentence; shown under the title, and used for the meta description, social cards and the feed."
date: 2025-12-04
tags: [lightning, security, dos, lnd]
featured_image: lnd_infinite_inbox_dos_header.png
---
```

`featured_image` is a bare filename resolved against `/images/`. It is
optional: a post without one renders correctly. Add `lastmod` only if a post
is revised after publication. Add `coauthors: ["Name"]` when a post has one.

URLs come from the directory: `content/lightning/foo.md` is served at
`/lightning/foo/`. A future non-Lightning topic is just a new directory under
`content/`.

## Structure

```
hugo.toml              site config
content/               the posts and pages
layouts/               templates
assets/css/            main.css and syntax.css, bundled and fingerprinted
static/                images, favicons; served verbatim
archetypes/            `hugo new` scaffolds
```

Math in posts is written as LaTeX between `$$` delimiters and rendered to
MathML at build time by `layouts/_markup/render-passthrough.html`. Nothing is
loaded at runtime to display it.

## Deployment

Pushing to `main` triggers `.github/workflows/deploy.yml`, which builds with
Hugo and publishes via `actions/deploy-pages`.

## Licensing

- Site code (`layouts/`, `assets/css/`, config, scripts): MIT. See `LICENSE`.
- Content (`content/`, `static/images/`): CC BY 4.0. See `LICENSE-CONTENT`.
