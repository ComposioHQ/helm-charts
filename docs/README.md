# Composio Helm Charts Documentation

This directory contains the GitHub Pages documentation for the Composio Helm Charts.

## Structure

- `index.html` - Main landing page with quick start guide
- `changelog.html` - Changelog for Docker images and Helm releases
- `load-tests.html` - Load test results with date range filtering
- `access-request.html` - On-premises access request form
- `assets/` - CSS and JavaScript files
- `data/` - JSON data files for dynamic content

## Features

- **Quick Start Guide**: Step-by-step installation instructions
- **Changelog**: Track all changes to Docker images and Helm releases
- **Load Test Results**: Performance metrics with date range filtering
- **Access Request Form**: Request on-premises access with detailed form
- **Responsive Design**: Mobile-friendly interface
- **Interactive Charts**: Performance visualization using Chart.js

## Deployment

The site is automatically deployed to GitHub Pages when changes are pushed to the main branch. The deployment is handled by the GitHub Actions workflow in `.github/workflows/deploy-pages.yml`.

## Local Development

To run the site locally:

1. Install Jekyll: `gem install jekyll bundler`
2. Navigate to the docs directory: `cd docs`
3. Install dependencies: `bundle install`
4. Start the server: `bundle exec jekyll serve`
5. Open http://localhost:4000 in your browser

## Customization

- Update `_config.yml` for site configuration
- Modify HTML files for content changes
- Edit `assets/style.css` for styling
- Update `assets/script.js` for interactive functionality
- Modify JSON files in `data/` for dynamic content
