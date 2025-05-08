# Mixing Spot and On-Demand Instances in a Pulsar Cluster

Mixing Spot and On-Demand instances in a Pulsar deployment provides an optimal balance between cost savings and reliability. Here's a detailed explanation of how to implement this hybrid approach effectively:

## Core Concepts for Mixed Fleet Management

### Node Group Segregation Strategies

There are several approaches to create a mixed fleet:

1. **Labeled Node Groups**: Create separate EKS node groups with distinct labels to differentiate Spot vs On-Demand
2. **Karpenter Provisioners**: Define multiple provisioners with different capacity types
3. **Node Taints and Tolerations**: Use Kubernetes taints to mark node types and tolerations in pod specs

## Detailed Implementation

### 1. Creating Separate Node Groups with eksctl

```yaml
# eksctl config for mixed node groups
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: pulsar-cluster
  region: us-east-1
nodeGroups:
  # On-Demand node group for critical components
  - name: pulsar-critical-ng
    instanceType: r5.4xlarge
    desiredCapacity: 3
    minSize: 3
    maxSize: 10
    availabilityZones: ["us-east-1a", "us-east-1b", "us-east-1c"]
    labels:
      role: critical
      lifecycle: on-demand
    tags:
      k8s.io/cluster-autoscaler/enabled: "true"
    iam:
      withAddonPolicies:
        autoScaler: true
  
  # Spot node group for non-critical components
  - name: pulsar-bookkeeper-spot-ng
    instanceTypes: ["r5.4xlarge", "r5a.4xlarge", "r5n.4xlarge"]
    desiredCapacity: 6
    minSize: 3
    maxSize: 20
    availabilityZones: ["us-east-1a", "us-east-1b", "us-east-1c"]
    labels:
      role: bookkeeper
      lifecycle: spot
    taints:
      - key: spot
        value: "true"
        effect: NoSchedule
    spot: true
    tags:
      k8s.io/cluster-autoscaler/enabled: "true"
```

### 2. Karpenter Provisioners for Mixed Fleet

```yaml
# On-demand provisioner for critical components
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: pulsar-ondemand
spec:
  requirements:
    - key: karpenter.sh/capacity-type
      operator: In
      values: ["on-demand"]
    - key: node.kubernetes.io/instance-type
      operator: In
      values: ["r5.4xlarge", "r5.8xlarge"]
    - key: topology.kubernetes.io/zone
      operator: In
      values: ["us-east-1a", "us-east-1b", "us-east-1c"]
  labels:
    lifecycle: on-demand
    workload-type: critical
  taints:
    - key: workload-type
      value: critical
      effect: NoSchedule
  limits:
    resources:
      cpu: 100
      memory: 400Gi

---
# Spot provisioner for cost-optimized components
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: pulsar-spot
spec:
  requirements:
    - key: karpenter.sh/capacity-type
      operator: In
      values: ["spot"]
    - key: node.kubernetes.io/instance-type
      operator: In
      values: ["r5.4xlarge", "r5.8xlarge", "r5a.4xlarge", "r5a.8xlarge"]
    - key: topology.kubernetes.io/zone
      operator: In
      values: ["us-east-1a", "us-east-1b", "us-east-1c"]
  labels:
    lifecycle: spot
    workload-type: cost-optimized
  taints:
    - key: workload-type
      value: cost-optimized
      effect: NoSchedule
  limits:
    resources:
      cpu: 200
      memory: 800Gi
```

### 3. Pod Configuration for Component Placement

#### Critical Components on On-Demand Nodes

```yaml
# Proxy deployment (critical component)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pulsar-proxy
spec:
  replicas: 3
  template:
    spec:
      nodeSelector:
        lifecycle: on-demand
      # No tolerations needed for regular nodes
      containers:
      - name: pulsar-proxy
        image: apachepulsar/pulsar:2.10.0
        resources:
          requests:
            memory: "4Gi"
            cpu: "2"
          limits:
            memory: "6Gi"
            cpu: "3"
```

#### ZooKeeper on On-Demand Nodes

```yaml
# ZooKeeper StatefulSet (critical component)
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: pulsar-zookeeper
spec:
  replicas: 3
  template:
    spec:
      # Explicit node selection for critical path components
      nodeSelector:
        lifecycle: on-demand
        workload-type: critical
      # Toleration for critical nodes if tainted
      tolerations:
      - key: workload-type
        operator: Equal
        value: critical
        effect: NoSchedule
      containers:
      - name: pulsar-zookeeper
        image: apachepulsar/pulsar:2.10.0
```

#### Mixed Fleet for Brokers

```yaml
# Broker StatefulSet with mixed fleet approach
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: pulsar-broker
spec:
  replicas: 10
  template:
    spec:
      # Using affinity for more nuanced scheduling
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              # Allow placement on either on-demand or spot
              - key: lifecycle
                operator: In
                values: ["on-demand", "spot"]
          preferredDuringSchedulingIgnoredDuringExecution:
          # Preference tiering - try on-demand first for 30% of brokers
          - weight: 100
            preference:
              matchExpressions:
              - key: lifecycle
                operator: In
                values: ["on-demand"]
              # Numerical constraint to get ~30% on-demand
              - key: node.kubernetes.io/instance-id
                operator: Lt
                values: ["3"]
      # Tolerations for both types of nodes
      tolerations:
      - key: workload-type
        operator: Equal
        value: critical
        effect: NoSchedule
      - key: workload-type
        operator: Equal
        value: cost-optimized
        effect: NoSchedule
      containers:
      - name: pulsar-broker
        image: apachepulsar/pulsar:2.10.0
```

#### BookKeeper Deployed Primarily on Spot

```yaml
# BookKeeper StatefulSet (primarily using spot)
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: pulsar-bookkeeper
spec:
  replicas: 15
  template:
    spec:
      # Explicit node selection for spot instances
      nodeSelector:
        workload-type: cost-optimized
      # Required toleration for spot nodes
      tolerations:
      - key: workload-type
        operator: Equal
        value: cost-optimized
        effect: NoSchedule
      containers:
      - name: pulsar-bookkeeper
        image: apachepulsar/pulsar:2.10.0
```

## Practical Implementation Techniques

### 1. Using Helm to Manage Mixed Deployments

```yaml
# values.yaml snippet for Pulsar Helm chart
proxy:
  nodeSelector:
    lifecycle: on-demand
  tolerations: []
  replicaCount: 3

zookeeper:
  nodeSelector:
    lifecycle: on-demand
  tolerations: []
  replicaCount: 3

broker:
  # Use affinity for more complex rules rather than nodeSelector
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: "kubernetes.io/os"
            operator: In
            values: ["linux"]
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
          - key: lifecycle
            operator: In
            values: ["on-demand"]
  # Allow scheduling on both types of nodes
  tolerations:
  - key: workload-type
    operator: Exists
    effect: NoSchedule
  replicaCount: 10
  # Annotation to influence scheduling ratios
  podAnnotations:
    cluster-autoscaler.kubernetes.io/safe-to-evict: "true"
    karpenter.sh/do-not-disrupt: "false"
    scheduling.karpenter.sh/capacity-type-target: "70% spot, 30% on-demand"

bookkeeper:
  nodeSelector:
    lifecycle: spot
  tolerations:
  - key: workload-type
    operator: Equal
    value: cost-optimized
    effect: NoSchedule
  replicaCount: 15
  podAnnotations:
    cluster-autoscaler.kubernetes.io/safe-to-evict: "true"
```

### 2. Heterogeneous Deployments for Brokers

For components like brokers where you want some instances on On-Demand and others on Spot, you can use multiple StatefulSets:

```yaml
# On-demand broker deployment
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: pulsar-broker-critical
spec:
  replicas: 3  # 30% of total brokers
  selector:
    matchLabels:
      app: pulsar
      component: broker
      tier: critical
  template:
    metadata:
      labels:
        app: pulsar
        component: broker
        tier: critical
    spec:
      nodeSelector:
        lifecycle: on-demand
      # Broker configuration...

---
# Spot broker deployment
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: pulsar-broker-spot
spec:
  replicas: 7  # 70% of total brokers
  selector:
    matchLabels:
      app: pulsar
      component: broker
      tier: spot
  template:
    metadata:
      labels:
        app: pulsar
        component: broker
        tier: spot
    spec:
      nodeSelector:
        lifecycle: spot
      tolerations:
      - key: workload-type
        operator: Equal
        value: cost-optimized
        effect: NoSchedule
      # Broker configuration...
```

### 3. Setting Capacity Distribution with Karpenter

Using Karpenter's EC2NodeClass and NodePool resources:

```yaml
# Define node classes
apiVersion: karpenter.sh/v1beta1
kind: EC2NodeClass
metadata:
  name: pulsar-ondemand-class
spec:
  amiFamily: AL2
  subnetSelector:
    Name: "pulsar-*"
  securityGroupSelector:
    Name: "pulsar-cluster-sg"
  instanceTypes: 
    - r5.4xlarge
    - r5.8xlarge
  capacityType: on-demand

---
apiVersion: karpenter.sh/v1beta1
kind: EC2NodeClass
metadata:
  name: pulsar-spot-class
spec:
  amiFamily: AL2
  subnetSelector:
    Name: "pulsar-*"
  securityGroupSelector:
    Name: "pulsar-cluster-sg"
  instanceTypes:
    - r5.4xlarge
    - r5.8xlarge
    - r5a.4xlarge
    - r5a.8xlarge
  capacityType: spot

---
# NodePool for critical workloads
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: pulsar-critical
spec:
  template:
    spec:
      nodeClassRef:
        name: pulsar-ondemand-class
      taints:
        - key: workload-type
          value: critical
          effect: NoSchedule
  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 168h  # 7 days
  limits:
    cpu: 100
    memory: 400Gi
  weight: 100  # Higher weight prioritizes this nodepool

---
# NodePool for cost-optimized workloads
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:  
  name: pulsar-costopt
spec:
  template:
    spec:
      nodeClassRef:
        name: pulsar-spot-class
      taints:
        - key: workload-type
          value: cost-optimized
          effect: NoSchedule
  disruption:
    consolidationPolicy: WhenEmpty
    expireAfter: 72h  # 3 days - shorter for spot instances
  limits:
    cpu: 200
    memory: 800Gi
  weight: 0  # Lower weight deprioritizes this nodepool
```

## Advanced Mixed-Fleet Management Techniques

### 1. Programmatically Controlling the Mix Ratio

You can dynamically adjust the mix ratio of Spot vs On-Demand based on conditions:

```yaml
# Horizontal Pod Autoscaler for on-demand brokers
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: pulsar-broker-critical-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: StatefulSet
    name: pulsar-broker-critical
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70

---
# KEDA ScaledObject for spot brokers with different scaling characteristics
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: pulsar-broker-spot-scaler
spec:
  scaleTargetRef:
    name: pulsar-broker-spot
    kind: StatefulSet
  minReplicaCount: 7
  maxReplicaCount: 50
  triggers:
  - type: prometheus
    metadata:
      serverAddress: http://prometheus-server.monitoring.svc.cluster.local
      metricName: broker_lag
      query: sum(pulsar_broker_publish_rate) / 10000
      threshold: "1"
  - type: prometheus
    metadata:
      serverAddress: http://prometheus-server.monitoring.svc.cluster.local
      metricName: broker_cpu
      query: sum(rate(container_cpu_usage_seconds_total{pod=~"pulsar-broker-spot.*"}[5m])) / sum(kube_pod_container_resource_limits{pod=~"pulsar-broker-spot.*",resource="cpu"})
      threshold: "0.7"
```

### 2. Spot Instance Interruption Handling

To gracefully handle Spot interruptions:

```yaml
# AWS Node Termination Handler with specific actions for Pulsar
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: aws-node-termination-handler
spec:
  selector:
    matchLabels:
      app: aws-node-termination-handler
  template:
    metadata:
      labels:
        app: aws-node-termination-handler
    spec:
      containers:
      - name: aws-node-termination-handler
        image: amazon/aws-node-termination-handler:v1.13.3
        args:
          - --pod-termination-grace-period=180
          - --enable-spot-interruption-draining
          - --enable-scheduled-event-draining
          - --webhook-url=http://pulsar-controller:8080/drain
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
```

### 3. Custom Controller for BookKeeper Rack Balancing

Create a custom controller to ensure BookKeeper instances are balanced across node types:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bookkeeper-rack-balancer
spec:
  replicas: 1
  template:
    spec:
      nodeSelector:
        lifecycle: on-demand
      containers:
      - name: bookkeeper-rack-balancer
        imagePullPolicy: Always
        image: custom/bookkeeper-rack-balancer:v1.0.0
        env:
        - name: MIN_ONDEMAND_BOOKIES_PER_RACK
          value: "1"  # Ensure at least 1 bookie per rack is on-demand
        - name: SPOT_TARGET_PERCENTAGE
          value: "80" # Target 80% spot bookies
```

## Operational Best Practices for Mixed Fleets

### 1. Set Up Ratio-Based Alerts

Create Prometheus alerts to monitor your spot/on-demand ratio:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: spot-ratio-alerts
spec:
  groups:
  - name: spot-ratio
    rules:
    - alert: SpotRatioTooLow
      expr: sum(kube_node_labels{label_lifecycle="spot"}) / sum(kube_node_labels{label_lifecycle=~"spot|on-demand"}) < 0.6
      for: 30m
      labels:
        severity: warning
      annotations:
        summary: "Spot instance ratio is below target"
        description: "The ratio of spot to on-demand instances is below the 60% target threshold"
```

### 2. Implement Component-Specific Deployment Logic

Different components can have different mixed-fleet strategies:

| Component | On-Demand % | Spot % | Rationale |
|-----------|-------------|--------|-----------|
| ZooKeeper | 100% | 0% | Critical metadata service, small footprint |
| Proxy | 100% | 0% | Client-facing gateway, need stability |
| Brokers | 30% | 70% | Mixed for load handling, on-demand for stability |
| BookKeeper | 20% | 80% | Distributed storage with rack awareness |

### 3. Create Custom Spot Drain Handlers

For graceful Pulsar component draining on Spot interruptions:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pulsar-component-drain-handler
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: drain-handler
        image: custom/pulsar-drain-handler:v1.0
        ports:
        - containerPort: 8080
        env:
        - name: BROKER_DRAIN_TIMEOUT_SECONDS
          value: "120"
        - name: BOOKKEEPER_DRAIN_TIMEOUT_SECONDS
          value: "180"
```

## Real-World Example: 70/30 Mixed Fleet Implementation

Here's a practical example of implementing a 70% Spot, 30% On-Demand mixed fleet with automatic rebalancing:

```yaml
# helm values.yaml for Apache Pulsar
proxy:
  replicaCount: 5
  # Critical component - 100% On-Demand
  nodeSelector:
    lifecycle: on-demand

zookeeper:
  replicaCount: 3
  # Critical component - 100% On-Demand
  nodeSelector:
    lifecycle: on-demand

broker:
  # No nodeSelector - will use affinity below
  replicaCount: 10
  affinity:
    # Complex logic to distribute brokers 70/30
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: kubernetes.io/os
            operator: In
            values: ["linux"]
      preferredDuringSchedulingIgnoredDuringExecution:
      # This weighting will produce roughly 30% on on-demand nodes
      - weight: 30
        preference:
          matchExpressions:
          - key: lifecycle
            operator: In
            values: ["on-demand"]
      - weight: 70
        preference:
          matchExpressions:
          - key: lifecycle
            operator: In
            values: ["spot"]
  # Accept both types of nodes
  tolerations:
  - key: workload-type
    operator: Exists
  
bookkeeper:
  replicaCount: 15
  # Use more complex scheduling for bookies
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchExpressions:
        - key: app
          operator: In
          values: ["pulsar"]
        - key: component
          operator: In  
          values: ["bookkeeper"]
      topologyKey: "topology.kubernetes.io/zone"
  affinity:
    # Make sure we have at least some on-demand bookies
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 20
        preference:
          matchExpressions:
          - key: lifecycle
            operator: In
            values: ["on-demand"]
      - weight: 80
        preference:
          matchExpressions:
          - key: lifecycle
            operator: In
            values: ["spot"]
  # Accept all node types
  tolerations:
  - key: workload-type
    operator: Exists
```

This comprehensive approach to mixing Spot and On-Demand instances in your Pulsar cluster allows you to:

1. Save up to 70-90% on the cost of Spot-eligible workloads
2. Maintain reliability with strategic On-Demand placement
3. Automatically handle instance interruptions
4. Dynamically adjust the ratio based on workload patterns
5. Implement component-specific strategies based on criticality

The key to success with this approach is proper node labeling, thoughtful scheduling rules, and intelligent interruption handling to ensure workloads are resilient against Spot instance reclamation.
