# Salesforce DX Project

This workspace is scaffolded for Salesforce DX development.

## Structure

- `sfdx-project.json`: Salesforce DX configuration
- `force-app/main/default/classes`: Apex classes
- `.vscode/`: editor settings and recommended extensions

## Setup

1. Install Salesforce CLI: https://developer.salesforce.com/tools/sfdxcli
2. Authenticate to your org:
   ```powershell
   sfdx auth:web:login -d -a DevHub
   ```
3. Push source to a scratch org:
   ```powershell
   sfdx force:source:push
   ```
