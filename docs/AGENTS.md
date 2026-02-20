# AGENTS.md — Pi Mobile Assistant Context

This file provides project-specific context to the AI assistant.
Place it in the app's documents directory to customize behavior.

## Project Structure

Describe your project files and database schemas here.
The assistant will read this file at session start to understand your workspace.

## Custom Instructions

Add any project-specific instructions, conventions, or preferences.

## Example

```
## Project: My Recipe App

### Database
- recipes.db: SQLite database with tables: recipes, ingredients, tags
- Schema: see schema.sql in project root

### Files
- /data/recipes/ — JSON recipe files
- /exports/ — Generated CSV exports

### Instructions
- Always use metric measurements
- When querying recipes, sort by date_added DESC
- Format ingredient lists as markdown tables
```
