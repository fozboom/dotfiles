#!/bin/bash
echo "Linking shared snippets..."

# ---------------------------- Snippets ----------------------------
# Path to the shared snippet file
SNIPPET_SOURCE="$HOME/dotfiles/common-snippets/python.json"

# Create directories if they don't exist
mkdir -p "$HOME/.config/Code/User/snippets"
mkdir -p "$HOME/.config/zed/snippets"
mkdir -p "$HOME/.config/Cursor/User/snippets"

# Create links (flag -f overwrites existing link if it exists)
ln -sf "$SNIPPET_SOURCE" "$HOME/.config/Code/User/snippets/python.code-snippets"
ln -sf "$SNIPPET_SOURCE" "$HOME/.config/zed/snippets/python.json"
ln -sf "$SNIPPET_SOURCE" "$HOME/.config/Cursor/User/snippets/python.json"

echo "Snippets linked successfully."

# ---------------------------- Zed ----------------------------
echo "Backing up Zed..."
if [ -d "$HOME/.config/zed" ] || [ -L "$HOME/.config/zed" ]; then
    mv "$HOME/.config/zed" "$HOME/.config/zed.backup"
fi
stow zed
echo "Zed installed successfully."

# ---------------------------- Cursor ----------------------------
echo "Backing up Cursor..."
if [ -d "$HOME/.config/Cursor" ] || [ -L "$HOME/.config/Cursor" ]; then
    mv "$HOME/.config/Cursor" "$HOME/.config/Cursor.backup"
fi
stow cursor
echo "Cursor installed successfully."

# ---------------------------- VS Code ----------------------------
echo "Backing up VS Code..."
if [ -d "$HOME/.config/Code" ] || [ -L "$HOME/.config/Code" ]; then
    mv "$HOME/.config/Code" "$HOME/.config/Code.backup"
fi
stow code
echo "VS Code installed successfully."


echo "Installation complete. Do you want to delete the backups? (y/n)"
read delete_backups
if [ "$delete_backups" == "y" ]; then
    rm -rf "$HOME/.config/zed.backup"
    rm -rf "$HOME/.config/Cursor.backup"
    rm -rf "$HOME/.config/Code.backup"
fi


