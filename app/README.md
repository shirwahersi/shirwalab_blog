# Shirwalab Blog

Personal tech blog built with [Hugo](https://gohugo.io/) and the [Congo](https://github.com/jpanther/congo) theme.

## Prerequisites

- [Hugo Extended](https://gohugo.io/installation/) v0.87.0 or later
- [Go](https://golang.org/dl/) 1.18 or later (for Hugo modules)
- AWS CLI (for deployment)

## Quick Start

### First-time Setup

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd shirwalab_blog/app
   ```

2. Initialize Hugo modules:
   ```bash
   make init
   ```

3. Start the development server:
   ```bash
   make serve
   ```

4. Open http://localhost:1313 in your browser

### Creating Content

Create a new blog post:
```bash
hugo new posts/my-new-post.md
```

This creates a new post in `content/posts/` with front matter template.

### Front Matter Example

```yaml
---
title: "My Post Title"
date: 2024-01-15
draft: true
description: "A brief description"
tags: ["tag1", "tag2"]
---
```

Set `draft: false` when ready to publish.

## Available Commands

| Command | Description |
|---------|-------------|
| `make init` | Initialize Hugo modules (first-time setup) |
| `make serve` | Start development server with drafts |
| `make build` | Build production site |
| `make update` | Update theme and dependencies |
| `make clean` | Clean build artifacts and module cache |
| `make deploy` | Build and deploy to AWS S3/CloudFront |

## Project Structure

```
app/
├── archetypes/        # Content templates
├── config/_default/   # Hugo configuration
│   ├── config.toml    # Main config
│   ├── params.toml    # Theme parameters
│   ├── menus.en.toml  # Navigation menus
│   └── module.toml    # Hugo modules config
├── content/
│   ├── posts/         # Blog posts
│   └── static/        # Static assets (images)
└── public/            # Generated site (git-ignored)
```

## Deployment

The site is deployed to AWS S3 and served via CloudFront.

```bash
make deploy
```

This will:
1. Clean the public directory
2. Build the production site
3. Sync to S3
4. Invalidate the CloudFront cache

## Theme Customization

Theme settings are in `config/_default/params.toml`. See the [Congo documentation](https://jpanther.github.io/congo/docs/) for all available options.

## License

Content is copyright. Theme (Congo) is MIT licensed.
