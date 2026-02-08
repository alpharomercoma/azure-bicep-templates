// =============================================================================
// Monitoring Module - Azure Monitor Metric Alert & Action Group
// =============================================================================
// Equivalent to AWS CloudWatch Alarm with EC2 Stop Action
//
// In AWS, CloudWatch directly stops the EC2 instance via alarm action.
// In Azure, the VM self-deallocates via REST API (handled by cloud-init).
// This metric alert provides cloud-level visibility and email notifications
// as an additional monitoring layer.
// =============================================================================

@description('Azure region for all resources')
param location string

@description('Base name for all resources')
param baseName string

@description('VM resource ID to monitor')
param vmResourceId string

@description('Email address for alert notifications (optional)')
param notificationEmail string = ''

// =============================================================================
// Action Group (equivalent to CloudWatch Alarm action target)
// =============================================================================
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: '${baseName}-ag'
  location: 'global'
  properties: {
    groupShortName: 'VMIdle'
    enabled: true
    emailReceivers: !empty(notificationEmail) ? [
      {
        name: 'AdminEmail'
        emailAddress: notificationEmail
        useCommonAlertSchema: true
      }
    ] : []
  }
}

// =============================================================================
// Metric Alert - CPU Idle Detection
// =============================================================================
// Equivalent to AWS CloudWatch Alarm:
//   - Metric: CPUUtilization < 5%
//   - Period: 5 minutes
//   - Evaluation periods: 3
//   - Total detection time: 15 minutes
//
// Azure Metric Alert configuration:
//   - Metric: Percentage CPU < 5%
//   - Aggregation: Average
//   - Window size: 15 minutes
//   - Evaluation frequency: 5 minutes
// =============================================================================
resource cpuIdleAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${baseName}-cpu-idle-alert'
  location: 'global'
  properties: {
    description: 'Alert when VM CPU utilization is below 5% for 15 minutes (inactivity detected). The VM will self-deallocate via its cloud-init monitoring script.'
    severity: 2
    enabled: true
    scopes: [
      vmResourceId
    ]
    evaluationFrequency: 'PT5M'   // Check every 5 minutes (matches AWS 5-min period)
    windowSize: 'PT15M'           // 15-minute window (matches AWS 3 x 5-min periods)
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'CPUIdle'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          metricName: 'Percentage CPU'
          operator: 'LessThan'
          threshold: 5
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
    autoMitigate: true
    targetResourceType: 'Microsoft.Compute/virtualMachines'
    targetResourceRegion: location
  }
}

// =============================================================================
// Outputs
// =============================================================================
output actionGroupId string = actionGroup.id
output alertId string = cpuIdleAlert.id
output alertName string = cpuIdleAlert.name
