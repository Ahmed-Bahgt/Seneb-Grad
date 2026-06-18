import os
import sys
import subprocess
import urllib.request
import urllib.error
import zipfile
import json
import time
import re

# Force UTF-8 for terminal to avoid encoding errors on Windows
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
BIN_DIR = os.path.join(CURRENT_DIR, "ngrok_bin")
NGROK_EXE = os.path.join(BIN_DIR, "ngrok.exe")
ZIP_PATH = os.path.join(BIN_DIR, "ngrok.zip")

NGROK_DOWNLOAD_URL = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-windows-amd64.zip"
API_CONFIG_PATH = os.path.abspath(os.path.join(CURRENT_DIR, "..", "lib", "utils", "api_config.dart"))

def check_and_download_ngrok():
    if not os.path.exists(BIN_DIR):
        os.makedirs(BIN_DIR)

    if not os.path.exists(NGROK_EXE):
        print("[*] Ngrok executable not found. Starting download...")
        try:
            print(f"[*] Downloading from: {NGROK_DOWNLOAD_URL}")
            urllib.request.urlretrieve(NGROK_DOWNLOAD_URL, ZIP_PATH)
            print("[*] Download complete. Extracting files...")
            with zipfile.ZipFile(ZIP_PATH, 'r') as zip_ref:
                zip_ref.extractall(BIN_DIR)
            print("[SUCCESS] Ngrok successfully extracted.")
        except Exception as e:
            print(f"[ERROR] Failed to download/extract Ngrok: {e}")
            sys.exit(1)
        finally:
            if os.path.exists(ZIP_PATH):
                try:
                    os.remove(ZIP_PATH)
                except Exception:
                    pass

def is_authtoken_configured():
    local_app_data = os.environ.get('LOCALAPPDATA', '')
    user_profile = os.environ.get('USERPROFILE', '')
    paths = [
        os.path.join(local_app_data, 'ngrok', 'ngrok.yml'),
        os.path.join(user_profile, '.config', 'ngrok', 'ngrok.yml')
    ]
    for p in paths:
        if os.path.exists(p):
            try:
                with open(p, 'r', encoding='utf-8') as f:
                    content = f.read()
                    if 'authtoken:' in content:
                        return True
            except Exception:
                pass
    return False

def configure_authtoken():
    if is_authtoken_configured():
        return True

    print("\n" + "="*70)
    print("                    NGROK AUTHTOKEN REQUIRED")
    print("="*70)
    print("Ngrok requires a free authtoken to start tunnels.")
    print("If you do not have one, please:")
    print("1. Sign up / Log in at: https://ngrok.com")
    print("2. Copy your authtoken from: https://dashboard.ngrok.com/get-started/your-authtoken")
    print("="*70 + "\n")
    
    try:
        token = input("Please paste your Ngrok Authtoken: ").strip()
        if not token:
            print("[ERROR] Authtoken cannot be empty. Exiting.")
            sys.exit(1)
        
        result = subprocess.run([NGROK_EXE, "config", "add-authtoken", token], capture_output=True, text=True)
        if result.returncode == 0:
            print("[SUCCESS] Authtoken configured successfully!\n")
            return True
        else:
            print(f"[ERROR] Failed to configure authtoken:\n{result.stderr}")
            sys.exit(1)
    except KeyboardInterrupt:
        print("\n[!] Setup cancelled by user. Exiting.")
        sys.exit(1)

def update_api_config(new_url):
    if not os.path.exists(API_CONFIG_PATH):
        print(f"[ERROR] Flutter api_config.dart not found at: {API_CONFIG_PATH}")
        sys.exit(1)
        
    with open(API_CONFIG_PATH, "r", encoding="utf-8") as f:
        content = f.read()
        
    pattern = r"(static\s+const\s+String\s+baseUrl\s*=\s*['\"])([^'\"]+)(['\"];)"
    match = re.search(pattern, content)
    
    if not match:
        print("[ERROR] Could not find 'static const String baseUrl' declaration in api_config.dart.")
        sys.exit(1)
        
    original_url = match.group(2)
    new_content = re.sub(pattern, rf"\g<1>{new_url}\g<3>", content)
    
    # Also search and replace aiHubBaseUrl if it's hardcoded and not equal to baseUrl
    # Currently: static const String aiHubBaseUrl = baseUrl; so it auto-updates, which is perfect.
    
    with open(API_CONFIG_PATH, "w", encoding="utf-8") as f:
        f.write(new_content)
        
    print(f"[SUCCESS] Updated baseUrl in api_config.dart:")
    print(f"          Old: {original_url}")
    print(f"          New: {new_url}")
    return content

def main():
    print("[*] Starting Ngrok Automation Script...")
    check_and_download_ngrok()
    configure_authtoken()
    
    temp_dir = os.path.join(CURRENT_DIR, "temp")
    if not os.path.exists(temp_dir):
        os.makedirs(temp_dir)
        
    log_path = os.path.join(temp_dir, "ngrok.log")
    
    print("[*] Launching Ngrok tunnel on port 8000...")
    log_file = open(log_path, "w", encoding="utf-8")
    
    ngrok_proc = None
    original_config = None
    
    try:
        ngrok_proc = subprocess.Popen(
            [NGROK_EXE, "http", "8000"],
            stdout=log_file,
            stderr=log_file,
            text=True
        )
        
        # Wait and poll local API for public URL
        public_url = None
        print("[*] Waiting for Ngrok tunnel to establish...")
        
        for i in range(12):
            time.sleep(1)
            # Check if process is still running
            if ngrok_proc.poll() is not None:
                print("[ERROR] Ngrok process terminated unexpectedly.")
                break
                
            try:
                with urllib.request.urlopen("http://127.0.0.1:4040/api/tunnels") as response:
                    data = json.loads(response.read().decode('utf-8'))
                    tunnels = data.get("tunnels", [])
                    for t in tunnels:
                        if t.get("proto") == "https":
                            public_url = t.get("public_url")
                            break
                        if not public_url and t.get("public_url"):
                            public_url = t.get("public_url")
                    if public_url:
                        break
            except urllib.error.URLError:
                pass
                
        if not public_url:
            print("[ERROR] Failed to retrieve public URL from Ngrok API.")
            print("[*] Reading ngrok.log for details:")
            try:
                log_file.close()
                with open(log_path, "r", encoding="utf-8") as f:
                    print(f.read())
            except Exception as le:
                print(f"Failed to read logs: {le}")
            sys.exit(1)
            
        # Update config and save original state
        original_config = update_api_config(public_url)
        
        print("\n" + "="*70)
        print(" 🎉 NGROK TUNNEL SUCCESSFULLY STARTED!")
        print("="*70)
        print(f" Public URL (HTTPS): {public_url}")
        print(f" Local Backend:       http://127.0.0.1:8000")
        print(f" api_config.dart:     UPDATED & SAVED")
        print("="*70)
        print("\n>>> PRESS Ctrl+C TO STOP NGROK AND RESTORE api_config.dart <<<\n")
        
        while True:
            time.sleep(1)
            
    except KeyboardInterrupt:
        print("\n[*] Shutting down and cleaning up...")
    finally:
        # Close log file if not already closed
        try:
            log_file.close()
        except Exception:
            pass
            
        # Restore configuration
        if original_config:
            try:
                with open(API_CONFIG_PATH, "w", encoding="utf-8") as f:
                    f.write(original_config)
                print("[SUCCESS] api_config.dart restored to original configuration.")
            except Exception as e:
                print(f"[ERROR] Failed to restore api_config.dart: {e}")
                
        # Terminate Ngrok
        if ngrok_proc and ngrok_proc.poll() is None:
            print("[*] Terminating Ngrok process...")
            ngrok_proc.terminate()
            try:
                ngrok_proc.wait(timeout=5)
                print("[SUCCESS] Ngrok process terminated.")
            except subprocess.TimeoutExpired:
                print("[!] Force killing Ngrok...")
                ngrok_proc.kill()
                ngrok_proc.wait()
                print("[SUCCESS] Ngrok process force killed.")

if __name__ == "__main__":
    main()
