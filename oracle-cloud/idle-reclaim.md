# Idle reclaim

Oracle may reclaim an Always Free instance that's idle. Its definition, on
the [Always Free resources page](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm):
over seven days, CPU at the 95th percentile, network, and (on A1) memory
all stay below 20%.

That's fair. Free capacity sitting unused helps nobody. But an always-on
free box needs an always-on reason to exist.

Give it a real job, not a fake one:

- nightly test runs against whatever you're building;
- a benchmark runner, with the hardware written down next to the numbers;
- a fuzzer with a time budget;
- a demo people actually use.

Real work keeps it above the line as a side effect. Burning CPU in a loop
to stay above 20% would work too, but it's leaving the engine running in
the car park, and it isn't what the allowance is for. There's deliberately
no keepalive script here.

To see where you stand, the instance's metrics are in the console under
the instance's Metrics tab, or:

```sh
oci monitoring metric-data summarize-metrics-data -c <compartment-ocid> \
    --namespace oci_computeagent \
    --query-text 'CpuUtilization[1h]{resourceId = "<instance-ocid>"}.percentile(0.95)'
```

If it does get reclaimed, that's what `network.sh` and `launch-a1.sh` are
for. Treat the box as something you can rebuild in ten minutes, and keep
anything you can't rebuild somewhere else.
