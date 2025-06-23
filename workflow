# .github/workflows/jfrog-token-rotation.yml
name: JFrog Token Rotation

on:
  schedule:
    - cron: '0 2 * * 1'  # Every Monday at 2 AM UTC
  workflow_dispatch:  # Manual trigger

jobs:
  rotate-jfrog-token:
    runs-on: ubuntu-latest
    
    steps:
    - name: Check and rotate JFrog token
      env:
        JFROG_URL: ${{ secrets.JFROG_URL }}
        JFROG_USERNAME: ${{ secrets.JFROG_USERNAME }}
        JFROG_PASSWORD: ${{ secrets.JFROG_PASSWORD }}
        CURRENT_TOKEN: ${{ secrets.JFROG_TOKEN }}
        TOKEN_SCOPE: ${{ secrets.TOKEN_SCOPE || 'applied-permissions/user' }}
      run: |
        echo "Checking current token expiration..."
        
        # Check token expiration
        token_info=$(curl -s -w "%{http_code}" \
          -H "Authorization: Bearer $CURRENT_TOKEN" \
          "$JFROG_URL/access/api/v1/tokens")
        
        http_code="${token_info: -3}"
        response_body="${token_info%???}"
        
        if [ "$http_code" != "200" ]; then
          echo "Token check failed (HTTP $http_code), proceeding with rotation"
          NEEDS_ROTATION=true
        else
          expires_in=$(echo "$response_body" | jq -r '.expires_in // 0')
          echo "Token expires in $expires_in seconds"
          
          # Rotate if expires within 7 days (604800 seconds)
          if [ "$expires_in" -lt 604800 ]; then
            echo "Token expires within 7 days, rotation needed"
            NEEDS_ROTATION=true
          else
            echo "Token is valid for more than 7 days"
            NEEDS_ROTATION=false
          fi
        fi
        
        if [ "$NEEDS_ROTATION" = "true" ]; then
          echo "Creating new token..."
          
          # Create new token
          new_token_response=$(curl -s \
            -u "$JFROG_USERNAME:$JFROG_PASSWORD" \
            -X POST \
            -H "Content-Type: application/json" \
            "$JFROG_URL/access/api/v1/tokens" \
            -d "{\"expires_in\": 2592000, \"scope\": \"$TOKEN_SCOPE\"}")
          
          new_token=$(echo "$new_token_response" | jq -r '.access_token // empty')
          
          if [ -z "$new_token" ]; then
            echo "Failed to create new token"
            echo "Response: $new_token_response"
            exit 1
          fi
          
          echo "New token created successfully"
          echo "NEW_TOKEN=$new_token" >> $GITHUB_ENV
        else
          echo "No rotation needed"
        fi

    - name: Update GitHub secret
      if: env.NEW_TOKEN
      uses: gliech/create-github-secret-action@v1
      with:
        name: JFROG_TOKEN
        value: ${{ env.NEW_TOKEN }}
        pa_token: ${{ secrets.GITHUB_TOKEN }}

    - name: Verify new token
      if: env.NEW_TOKEN
      env:
        JFROG_URL: ${{ secrets.JFROG_URL }}
      run: |
        echo "Testing new token..."
        
        test_response=$(curl -s -w "%{http_code}" \
          -H "Authorization: Bearer ${{ env.NEW_TOKEN }}" \
          "$JFROG_URL/artifactory/api/system/ping")
        
        test_http_code="${test_response: -3}"
        
        if [ "$test_http_code" = "200" ]; then
          echo "New token is working correctly"
        else
          echo "New token verification failed (HTTP $test_http_code)"
          exit 1
        fi
