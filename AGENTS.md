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

### Agent Script Deployment

- Do not deploy `AiAuthoringBundle` or `.agent` files with `sf project deploy`. The Metadata API returns `Not available for deploy for this API version` for these files.
- Use an org-supported API version for Agent Script commands. For the current project and org, explicitly use `--api-version 67.0`; the `sourceApiVersion` in `sfdx-project.json` is older and must not be relied on for this workflow.
- Validate, publish, and activate the authoring bundle in this order:

```sh
sf agent validate authoring-bundle --api-name <BUNDLE_API_NAME> --target-org <ORG> --api-version 67.0 --json
sf agent publish authoring-bundle --api-name <BUNDLE_API_NAME> --target-org <ORG> --api-version 67.0 --skip-retrieve --json
sf agent activate --api-name <BUNDLE_API_NAME> --target-org <ORG> --api-version 67.0 --json
```

- `sf agent publish authoring-bundle` compiles the Agent Script and creates or updates its associated `BotDefinition` and version metadata. Publishing does not make the agent available to users; activation is required.
- Deploy Flows or other metadata that reference the agent only after the authoring bundle has been published. Use `sf project deploy` for those dependent metadata components, not for the authoring bundle itself.
- If a routing Flow must take effect immediately, set its metadata status to `Active`, deploy it, and verify that the Flow definition's active version matches its latest version.

## Validation

Run:

sf apex run test --test-level RunLocalTests

## Review

Check:
- Governor Limits
- Sharing model
- Security Review considerations
- Test coverage
