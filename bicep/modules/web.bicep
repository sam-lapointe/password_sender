@description('The Service Plan name.')
param servicePlanName string

@description('The web app name.')
param webAppName string

@description('The location of the resources.')
param location string

param tags object

@description('The Workspace ID to store logs')
param workspaceID string

@description('The User Managed Identity Client ID')
param umiClientID string

@description('The User Managed Identity ID.')
param umiID string

param keyVaultResourceEndpoint string

@description('Deploy the code from the bicep deployment.')
param deployCode bool 

@description('The URI to download the Github repository.')
param codeURI string = 'https://github.com/sam-lapointe/password_sender/archive/refs/heads/main.zip'


resource servicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: servicePlanName
  location: location
  tags: tags
  sku: {
    name: 'B1'
    tier: 'Basic'
  }
  kind: 'linux'
  properties: {
    reserved: true
    targetWorkerSizeId: 0
    targetWorkerCount: 1
  }
}

resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: webAppName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${umiID}': {}
    }
  }
  properties: {
    serverFarmId: servicePlan.id
    clientAffinityEnabled: false
    virtualNetworkSubnetId: null
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.12'
      alwaysOn: false
      ftpsState: 'FtpsOnly'
      appSettings: [
        {
          name: 'AZURE_CLIENT_ID'
          value: umiClientID
        }
        {
          name: 'AZURE_KEYVAULT_RESOURCEENDPOINT'
          value: keyVaultResourceEndpoint
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
      ]
    }
  }
}

resource webDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: webApp
  name: '${webAppName}-logs'
  properties: {
    logAnalyticsDestinationType: null
    workspaceId: workspaceID
    logs: [
      {
        category: 'AppServiceHTTPLogs'
        categoryGroup: null
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
      }
      {
        category: 'AppServiceConsoleLogs'
        categoryGroup: null
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
      }
      {
        category: 'AppServiceAppLogs'
        categoryGroup: null
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
      }
      {
        category: 'AppServiceAuditLogs'
        categoryGroup: null
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
      }
      {
        category: 'AppServiceIPSecAuditLogs'
        categoryGroup: null
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
      }
      {
        category: 'AppServicePlatformLogs'
        categoryGroup: null
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
      }
    ]
    metrics: [
      {
        timeGrain: null
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
        category: 'AllMetrics'
      }
    ]
  }
}

resource pythonCodeDeployment 'Microsoft.Resources/deploymentScripts@2023-08-01' = if (deployCode) {
  name: 'pythonCodeDeployment'
  location: location
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${umiID}': {}
    }
  }
  properties: {
    azPowerShellVersion: '11.0'
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'PT1H'

    environmentVariables: [
      {
        name: 'codeURI'
        value: codeURI
      }
      {
        name: 'resourceGroupName'
        value: resourceGroup().name
      }
      {
        name: 'webAppName'
        value: webApp.name
      }
      {
        name: 'AZURE_CLIENT_ID'
        value: umiClientID
      }
    ]
  
    scriptContent: '''
      Invoke-WebRequest -Uri $env:codeURI -OutFile ./code.zip
      Expand-Archive ./code.zip
      Compress-Archive -Path ./code/password_sender-main/* -DestinationPath ./app.zip
      Connect-AzAccount -Identity
      $app = Get-AzWebApp -ResourceGroupName $env:resourceGroupName -Name $env:webAppName
      Publish-AzWebApp -WebApp $app -ArchivePath ./app.zip -Force
    '''
  }
}

output hostingPlanName string = servicePlan.name
