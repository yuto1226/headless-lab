# Salesforce Development Rules

This is a Salesforce DX project.

## Requirements

- Use Lightning Web Components
- Create Apex tests for Apex changes
- Follow Salesforce best practices
- Bulkify Apex code
- Check CRUD and FLS

## Agent Script

- When working with Agent Script, always refer to `.airules/AGENT_SCRIPT.md`.
- Before generating Agent Script, complete the Discovery Questions in `.airules/AGENT_SCRIPT.md`.
- After changing Agent Script, complete the Validation Checklist in `.airules/AGENT_SCRIPT.md`.

## Validation

Run:

sf apex run test --test-level RunLocalTests

## Review

Check:
- Governor Limits
- Sharing model
- Security Review considerations
- Test coverage
