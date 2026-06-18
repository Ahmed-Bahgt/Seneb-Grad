import requests
import sys

def main():
    print("Testing local server...")
    try:
        r = requests.get("http://localhost:8000/", timeout=5)
        print("Status code:", r.status_code)
        print("Response body:", r.json())
        if r.status_code == 200 and r.json().get("status") == "online":
            print("SUCCESS: The backend server is running and healthy!")
            sys.exit(0)
        else:
            print("FAILURE: Server returned unexpected response.")
            sys.exit(1)
    except Exception as e:
        print("ERROR: Could not connect to the server. Is it running?")
        print(e)
        sys.exit(1)

if __name__ == "__main__":
    main()
