# The image the workbench builds and the Fargate task runs.
#
# The _monolithic template wrote this file from inside the bastion userdata with a shell "echo ... >
# Dockerfile", alongside a second echo that wrote its own copy of monitoring.py - so the monitoring.py already
# sitting in this directory was never used, and the two drifted apart with nothing to say so. Both files are
# read from here now and shipped to the instance by the root module, which makes this directory the one
# place either of them is edited.
FROM python:3.13-slim
WORKDIR /app
COPY monitoring.py .
RUN pip install --no-cache-dir Flask
# Port 80 inside the container, which is what the task definition's port mapping and the target group's
# health check both expect.
EXPOSE 80
CMD ["python", "monitoring.py"]
