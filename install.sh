#!/bin/bash
set -e  # Exit immediately if a command exits with non-zero status

# === CONFIG ===
CONTAINER_NAME="awesome-n8n"
WORKFLOW_DIR="./workflows"

# === FUNCTIONS ===
show_usage() {
  echo "Usage: $0 [OPTION] WORKFLOW_FILE"
  echo "Import n8n workflows into a running container"
  echo
  echo "Options:"
  echo "  -c, --container NAME   Specify container name (default: $CONTAINER_NAME)"
  echo "  -d, --directory DIR    Specify workflows directory (default: $WORKFLOW_DIR)"
  echo "  -a, --all              Import all workflow files from directory"
  echo "  -h, --help             Display this help and exit"
  echo
  echo "Examples:"
  echo "  $0 my-workflow.json           # Import a specific workflow"
  echo "  $0 -a                         # Import all workflows from directory"
  echo "  $0 -c custom-n8n my-flow.json # Import using custom container name"
}

# Function to check if container exists and is running
check_container() {
  local container_id
  container_id=$(docker ps -qf "name=$CONTAINER_NAME")
  
  if [ -z "$container_id" ]; then
    echo "❌ Error: No running container found with name '$CONTAINER_NAME'"
    echo "💡 Tip: Make sure the container is running with: docker ps"
    exit 1
  fi
  
  echo "$container_id"
}

# Function to import a single workflow
import_workflow() {
  local workflow_file="$1"
  local container_id="$2"
  
  # Check if workflow file exists
  if [ ! -f "$WORKFLOW_DIR/$workflow_file" ]; then
    echo "❌ Error: Workflow file '$WORKFLOW_DIR/$workflow_file' not found"
    return 1
  fi
  
  echo "📂 Creating workflows directory in container if it doesn't exist..."
  docker exec -u node "$container_id" sh -c "mkdir -p /workflows"
  
  echo "📦 Copying '$workflow_file' to container..."
  if ! docker cp "$WORKFLOW_DIR/$workflow_file" "$container_id:/workflows/$workflow_file"; then
    echo "❌ Error: Failed to copy workflow file to container"
    return 1
  fi
  
  echo "🔄 Importing workflow: $workflow_file"
  if docker exec -u node "$container_id" sh -c "n8n import:workflow --input='/workflows/$workflow_file'"; then
    echo "✅ Successfully imported: $workflow_file"
    return 0
  else
    echo "❌ Failed to import: $workflow_file"
    return 1
  fi
}

# Function to import all workflows
import_all_workflows() {
  local container_id="$1"
  local success_count=0
  local fail_count=0
  local workflow_count=0
  
  echo "📂 Creating workflows directory in container if it doesn't exist..."
  docker exec -u node "$container_id" sh -c "mkdir -p /workflows"
  
  # Check if directory exists and has JSON files
  if [ ! -d "$WORKFLOW_DIR" ] || [ -z "$(find "$WORKFLOW_DIR" -name "*.json" -type f)" ]; then
    echo "❌ Error: No workflow files (.json) found in '$WORKFLOW_DIR'"
    return 1
  fi
  
  # Copy all workflow files to container
  echo "📦 Copying all workflow files to container..."
  docker cp "$WORKFLOW_DIR/." "$container_id:/workflows/"
  
  echo "🔄 Importing all workflows..."
  if docker exec -u node "$container_id" sh -c "n8n import:workflow --separate --input='/workflows'"; then
    echo "✅ Successfully imported all workflows"
    return 0
  else
    echo "❌ Some workflows may have failed to import"
    return 1
  fi
}

# === CHECK IF DOCKER IS INSTALLED ===
if ! command -v docker &> /dev/null; then
  echo "❌ Error: Docker is not installed or not in your PATH"
  echo "🔧 Please install Docker: https://docs.docker.com/get-docker/"
  exit 1
fi

# === PARSE COMMAND LINE ARGUMENTS ===
IMPORT_ALL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_usage
      exit 0
      ;;
    -c|--container)
      CONTAINER_NAME="$2"
      shift 2
      ;;
    -d|--directory)
      WORKFLOW_DIR="$2"
      shift 2
      ;;
    -a|--all)
      IMPORT_ALL=true
      shift
      ;;
    -*)
      echo "❌ Error: Unknown option $1"
      show_usage
      exit 1
      ;;
    *)
      WORKFLOW_FILE="$1"
      shift
      ;;
  esac
done

# === VALIDATE INPUTS ===
if [ "$IMPORT_ALL" = false ] && [ -z "$WORKFLOW_FILE" ]; then
  echo "❌ Error: Please provide a workflow filename or use --all"
  show_usage
  exit 1
fi

# === MAIN EXECUTION ===
CONTAINER_ID=$(check_container)

# Create workflow directory if it doesn't exist
mkdir -p "$WORKFLOW_DIR"

if [ "$IMPORT_ALL" = true ]; then
  import_all_workflows "$CONTAINER_ID"
  result=$?
else
  import_workflow "$WORKFLOW_FILE" "$CONTAINER_ID"
  result=$?
fi

exit $result