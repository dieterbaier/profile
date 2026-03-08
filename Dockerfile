# ---------------------------
# Base Image: Java + Tools
# ---------------------------
FROM openjdk:22-jdk-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    pandoc \
    graphviz \
    unzip \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Arbeitsverzeichnis
WORKDIR /app

# Flexible entrypoint – beliebige Commands
ENTRYPOINT []