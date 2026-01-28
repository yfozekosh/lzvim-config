# Azure SQL Server Authentication Guide

This guide explains how to connect to Azure SQL Server using Azure Active Directory authentication in nvim-dbee.

## Prerequisites

- Azure SQL Database or Azure SQL Managed Instance
- Appropriate Azure AD permissions
- Azure CLI (optional, for `ActiveDirectoryDefault`)

## Quick Start

Add Azure AD authentication to your SQL Server connection by including the `fedauth` parameter in the connection URL:

```lua
require("dbee").setup {
  sources = {
    require("dbee.sources").MemorySource:new({
      {
        name = "Azure SQL Database",
        type = "sqlserver",
        url = "sqlserver://myserver.database.windows.net?database=mydb&fedauth=ActiveDirectoryDefault",
      },
    }),
  },
}
```

## Authentication Methods

### 1. ActiveDirectoryDefault (Recommended)

This is equivalent to `sqlcmd -G` and uses the Azure credential chain:
- Environment variables
- Managed identity (if running in Azure)
- Azure CLI credentials
- Interactive browser authentication

```lua
{
  name = "Azure SQL - Default",
  type = "sqlserver",
  url = "sqlserver://myserver.database.windows.net?database=mydb&fedauth=ActiveDirectoryDefault",
}
```

### 2. ActiveDirectoryManagedIdentity

Uses managed identity (system-assigned or user-assigned). Best for applications running in Azure:

```lua
{
  name = "Azure SQL - Managed Identity",
  type = "sqlserver",
  url = "sqlserver://myserver.database.windows.net?database=mydb&fedauth=ActiveDirectoryManagedIdentity",
}
```

For user-assigned managed identity, specify the client ID:

```lua
{
  name = "Azure SQL - User Managed Identity",
  type = "sqlserver",
  url = "sqlserver://user-assigned-identity-id@myserver.database.windows.net?database=mydb&fedauth=ActiveDirectoryManagedIdentity",
}
```

### 3. ActiveDirectoryServicePrincipal

Uses service principal authentication with client ID and secret:

```lua
{
  name = "Azure SQL - Service Principal",
  type = "sqlserver",
  url = "sqlserver://client-id@myserver.database.windows.net?database=mydb&fedauth=ActiveDirectoryServicePrincipal&password=client-secret&tenant id=tenant-id",
}
```

**Security Best Practice:** Use environment variables for secrets:

```lua
{
  name = "Azure SQL - Service Principal (Secure)",
  type = "sqlserver",
  url = "sqlserver://{{ env \"AZURE_CLIENT_ID\" }}@myserver.database.windows.net?database=mydb&fedauth=ActiveDirectoryServicePrincipal&password={{ env \"AZURE_CLIENT_SECRET\" }}&tenant id={{ env \"AZURE_TENANT_ID\" }}",
}
```

### 4. ActiveDirectoryPassword

Uses username and password authentication:

```lua
{
  name = "Azure SQL - Password",
  type = "sqlserver",
  url = "sqlserver://username@myserver.database.windows.net?database=mydb&fedauth=ActiveDirectoryPassword&password=user-password",
}
```

**Security Best Practice:** Use environment variables:

```lua
{
  name = "Azure SQL - Password (Secure)",
  type = "sqlserver",
  url = "sqlserver://{{ env \"AZURE_SQL_USER\" }}@myserver.database.windows.net?database=mydb&fedauth=ActiveDirectoryPassword&password={{ env \"AZURE_SQL_PASSWORD\" }}",
}
```

## Complete Example Configuration

```lua
require("dbee").setup {
  sources = {
    require("dbee.sources").MemorySource:new({
      -- Development: Use Azure CLI credentials
      {
        name = "Dev - Azure SQL",
        type = "sqlserver",
        url = "sqlserver://dev-server.database.windows.net?database=devdb&fedauth=ActiveDirectoryDefault",
      },
      -- Production: Use Managed Identity
      {
        name = "Prod - Azure SQL",
        type = "sqlserver",
        url = "sqlserver://prod-server.database.windows.net?database=proddb&fedauth=ActiveDirectoryManagedIdentity",
      },
      -- CI/CD: Use Service Principal with secrets from environment
      {
        name = "CI - Azure SQL",
        type = "sqlserver",
        url = "sqlserver://{{ env \"AZURE_CLIENT_ID\" }}@ci-server.database.windows.net?database=cidb&fedauth=ActiveDirectoryServicePrincipal&password={{ env \"AZURE_CLIENT_SECRET\" }}&tenant id={{ env \"AZURE_TENANT_ID\" }}",
      },
    }),
  },
}
```

## Environment Variables Setup

For service principal authentication:

```bash
export AZURE_CLIENT_ID="your-client-id"
export AZURE_CLIENT_SECRET="your-client-secret"
export AZURE_TENANT_ID="your-tenant-id"
```

For password authentication:

```bash
export AZURE_SQL_USER="your-username"
export AZURE_SQL_PASSWORD="your-password"
```

## Using Azure CLI for Default Authentication

1. Install Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli
2. Login: `az login`
3. Set subscription (if needed): `az account set --subscription "your-subscription"`
4. Use `ActiveDirectoryDefault` in your connection

## Troubleshooting

### "Login failed for user"
- Ensure your Azure AD user/service principal has access to the database
- Check that you're using the correct database name in the URL

### "AADSTS errors"
- Verify your tenant ID is correct
- Ensure service principal credentials are valid
- Check that the service principal has the required permissions

### "Cannot open server"
- Verify the server name is correct (should include `.database.windows.net`)
- Check that firewall rules allow your IP address
- Ensure the database name exists

## Additional Connection Parameters

You can add other standard SQL Server connection parameters:

```lua
{
  name = "Azure SQL - Custom Settings",
  type = "sqlserver",
  url = "sqlserver://myserver.database.windows.net?database=mydb&fedauth=ActiveDirectoryDefault&encrypt=true&connection timeout=30",
}
```

Common parameters:
- `encrypt=true|false` - Enable/disable encryption (default: true for Azure SQL)
- `connection timeout=30` - Connection timeout in seconds
- `app name=nvim-dbee` - Application name for monitoring

## References

- [go-mssqldb Azure AD documentation](https://github.com/microsoft/go-mssqldb#azure-active-directory-authentication)
- [Azure SQL authentication methods](https://docs.microsoft.com/en-us/azure/azure-sql/database/authentication-aad-overview)
