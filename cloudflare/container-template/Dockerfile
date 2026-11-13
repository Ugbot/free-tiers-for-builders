# Stand-in workload: replace with your own. Keep the TTL wrapper.
# Images must be linux/amd64; deploy.sh builds with --platform.
FROM busybox:1.36
EXPOSE 8080
CMD ["sh", "-c", "exec timeout \"${AGENT_TTL_SECONDS:-7200}\" httpd -f -p 8080 -h /tmp"]
