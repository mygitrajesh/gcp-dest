#!/bin/bash

set -e

CONFIG_FILE="config.json"

load_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "❌ Config file $CONFIG_FILE not found!"
    exit 1
  fi

  shared_source_repos=($(jq -r '.shared_source_repos[]' "$CONFIG_FILE"))
  destination_repos=($(jq -r '.destination_repos[]' "$CONFIG_FILE"))
  module_paths=($(jq -r '.module_paths[]' "$CONFIG_FILE"))
  parent_paths=($(jq -r '.parent_paths[]' "$CONFIG_FILE"))

  if [[ ${#shared_source_repos[@]} -ne ${#destination_repos[@]} ]] || \
     [[ ${#shared_source_repos[@]} -ne ${#module_paths[@]} ]] || \
     [[ ${#shared_source_repos[@]} -ne ${#parent_paths[@]} ]]; then
      echo "❌ Configuration arrays in '$CONFIG_FILE' are not of the same length."
      exit 1
  fi
}

create_work_dir() {
  WORK_DIR=$(mktemp -d)
  echo "📁 Working directory: $WORK_DIR"
}

clone_repo() {
  local repo_url=$1
  local target_dir=$2
  echo "🚀 Cloning $repo_url..."
  
  # Debugging: Print GITLAB_TOKEN
  echo "GITLAB_TOKEN: ${GITLAB_TOKEN}"
  
  # Use the GITLAB_TOKEN for authentication
  git clone --quiet "https://oauth2:${GITLAB_TOKEN}@${repo_url#https://}" "$target_dir" || { echo "❌ Failed to clone $repo_url"; exit 1; }
}

copy_module_content() {
  local src_dir=$1
  local dst_dir=$2
  local module_path=$3
  local parent_path=$4

  SOURCE_PATH="$src_dir/$module_path"
  DEST_PATH="$dst_dir/$parent_path"

  echo "📦 Copying module from '$SOURCE_PATH' to '$DEST_PATH'..."
  mkdir -p "$DEST_PATH"
  cp -r "$SOURCE_PATH/"* "$DEST_PATH/"
}

commit_and_push_changes() {
  local repo_dir=$1
  local module_path=$2

  cd "$repo_dir"
  git add .
  git commit -m "chore: copied module from $module_path" || echo "⚠️ Nothing to commit"

  CURRENT_BRANCH=$(git symbolic-ref --short HEAD)
  echo "📤 Pushing changes to branch: $CURRENT_BRANCH"
  git push origin "$CURRENT_BRANCH" || { echo "❌ Failed to push changes"; exit 1; }
}

copy_tags() {
  local src_dir=$1
  local dst_dir=$2

  cd "$src_dir"
  TAGS=$(git tag -l)

  cd "$dst_dir"
  for tag in $TAGS; do
    if git rev-parse "$tag" >/dev/null 2>&1; then
      echo "⚠️ Tag $tag already exists. Skipping..."
    else
      echo "🏷️  Copying tag: $tag"
      git tag "$tag"
      git push origin "$tag"
    fi
  done
}

cleanup() {
  rm -rf "$WORK_DIR"
  echo "🧹 Cleaned up working directory."
}

process_repos() {
  for i in "${!shared_source_repos[@]}"; do
    echo ""
    echo "🔁 Processing entry [$((i+1))]:"
    echo "   Source Repo     : ${shared_source_repos[$i]}"
    echo "   Destination Repo: ${destination_repos[$i]}"
    echo "   Module Path     : ${module_paths[$i]}"
    echo "   Parent Path     : ${parent_paths[$i]}"

    SRC_DIR="$WORK_DIR/source_$i"
    DST_DIR="$WORK_DIR/dest_$i"

    clone_repo "${shared_source_repos[$i]}" "$SRC_DIR"
    clone_repo "${destination_repos[$i]}" "$DST_DIR"
    copy_module_content "$SRC_DIR" "$DST_DIR" "${module_paths[$i]}" "${parent_paths[$i]}"
    commit_and_push_changes "$DST_DIR" "${module_paths[$i]}"
    copy_tags "$SRC_DIR" "$DST_DIR"

    echo "✅ Completed processing for module '${module_paths[$i]}'."
  done
}

main() {
  load_config
  create_work_dir
  process_repos
  cleanup
}

main
