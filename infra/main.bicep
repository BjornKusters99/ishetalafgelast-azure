@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Globally unique, lowercase Azure Container Registry name.')
@minLength(5)
@maxLength(50)
param registryName string

@description('Container Apps environment name.')
param environmentName string = 'cae-ishetalafgelast-test'

@description('Container App name.')
param appName string = 'ca-ishetalafgelast-test'

@description('Public bootstrap image. Replaced by manual test deployment.')
param bootstrapImage string = 'nginxinc/nginx-unprivileged:1.29-alpine'

var workspaceName = 'law-${appName}'

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: registryName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
  }
}

resource environment 'Microsoft.App/managedEnvironments@2025-07-01' = {
  name: environmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: workspace.properties.customerId
        sharedKey: workspace.listKeys().primarySharedKey
      }
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

resource app 'Microsoft.App/containerApps@2025-07-01' = {
  name: appName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    environmentId: environment.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
      }
    }
    template: {
      containers: [
        {
          name: 'web'
          image: bootstrapImage
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          probes: [
            {
              type: 'Startup'
              tcpSocket: {
                port: 8080
              }
              initialDelaySeconds: 1
              periodSeconds: 5
              failureThreshold: 24
            }
            {
              type: 'Readiness'
              tcpSocket: {
                port: 8080
              }
              periodSeconds: 5
            }
            {
              type: 'Liveness'
              tcpSocket: {
                port: 8080
              }
              periodSeconds: 10
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 3
      }
    }
  }
}

output appName string = app.name
output appFqdn string = app.properties.configuration.ingress.fqdn
output appPrincipalId string = app.identity.principalId
output registryLoginServer string = registry.properties.loginServer
output registryId string = registry.id
