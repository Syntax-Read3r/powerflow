# Changelog

All notable changes to PowerFlow will be documented in this file.

## [Unreleased]

### Planning
- Additional database providers
- Testing framework integration
- Enhanced Docker optimizations

## [1.0.4] - 10-07-2025

### Added
- 🚀 **Professional Next.js Project Creator**: `create-next` / `create-n` command
  - **Database Selection**: Choose from PostgreSQL+Prisma, Supabase, MongoDB, MySQL+Prisma, or SQLite+Prisma
  - **Complete CI/CD Pipeline**: 3 GitHub Actions workflows (ci.yml, docker-build.yml, deploy.yml)
  - **Docker Integration**: Development and production Docker configurations with database services
  - **Enterprise Structure**: Professional folder organization with all necessary directories
  - **Comprehensive Documentation**: API docs, development guide, and deployment guide auto-generated
  - **Database-Specific Configurations**: Tailored setup for each database type with proper connection strings
  - **TypeScript Ready**: Full TypeScript support with database-specific type definitions
  - **Beautiful Interface**: Same fzf-powered interface as `git-a` with database selection
- 🏷️ **Version release workflow**: `git-a -VersionRelease` / `git-a -vr` 
- 🤖 **GitHub Actions integration**: Automatic release creation when version tags are pushed
- 🎯 **One-command releases**: Update version → `git-a -vr` → Automatic release generation
- ✅ **Smart release validation**: Ensures profile version matches git tag
- 📦 **Auto-generated release assets**: install.ps1, uninstall.ps1, and release notes

### Enhanced
- `git-a` function now supports version release workflow
- Help documentation updated with new release commands and `create-next` functionality
- Release process streamlined from manual to automated
- `pwsh-h` help system expanded with comprehensive Next.js project creation documentation

### Technical Details
- **`create-next`**: Creates production-ready Next.js applications with:
  - Latest Next.js 15+ with App Router, TypeScript, Tailwind CSS, ESLint
  - Database integration: Prisma schemas, Supabase client, or Mongoose models
  - Docker Compose configurations for development and production
  - GitHub Container Registry integration
  - Automated dependency installation based on database choice
  - Environment variable templates for each database type
  - Professional npm scripts for database operations and Docker management
