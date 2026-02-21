# Check if uv is installed
if (!(Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Host "Installing uv..."
    powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
}

# Create venv if it doesn't exist
if (!(Test-Path .venv)) {
    Write-Host "Creating virtual environment..."
    uv venv
}

# Source it
Write-Host "Virtual environment ready. Use '.\.venv\Scripts\activate.ps1' to activate."
