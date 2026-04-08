//go:build windows

package gobackend

func dupOutputFD(fd int) (int, error) {
	// Windows build is primarily for local tooling/tests.
	// Android runtime uses the !windows implementation.
	return fd, nil
}

func truncateFD(fd int) error {
	return nil
}

func seekFDStart(fd int) error {
	return nil
}

func closeFD(fd int) error {
	return nil
}

func isBestEffortTruncateError(err error) bool {
	return true
}

func isBadFD(err error) bool {
	return false
}
