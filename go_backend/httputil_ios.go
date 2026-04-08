//go:build ios

package gobackend

import (
	"net/http"
)

// iOS version: uTLS is not supported on iOS due to cgo DNS resolver issues
// Fall back to standard HTTP client

// GetCloudflareBypassClient returns the standard HTTP client on iOS
// uTLS is not available on iOS due to cgo DNS resolver compatibility issues
func GetCloudflareBypassClient() *http.Client {
	return sharedClient
}

// DoRequestWithCloudflareBypass on iOS just uses the standard client
// uTLS Chrome fingerprint bypass is not available on iOS
func DoRequestWithCloudflareBypass(req *http.Request) (*http.Response, error) {
	req.Header.Set("User-Agent", getRandomUserAgent())
	resp, err := sharedClient.Do(req)
	if err != nil {
		CheckAndLogISPBlocking(err, req.URL.String(), "HTTP")
	}
	return resp, err
}
