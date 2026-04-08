package gobackend

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

type ISRCIndex struct {
	index     map[string]string // ISRC (uppercase) -> file path
	outputDir string
	buildTime time.Time
	mu        sync.RWMutex
}

var (
	isrcIndexCache   = make(map[string]*ISRCIndex)
	isrcIndexCacheMu sync.RWMutex
	isrcBuildingMu   sync.Map // Per-directory build lock to prevent concurrent builds
	isrcIndexTTL     = 5 * time.Minute
)

func GetISRCIndex(outputDir string) *ISRCIndex {
	// Fast path: check cache first
	isrcIndexCacheMu.RLock()
	idx, exists := isrcIndexCache[outputDir]
	isrcIndexCacheMu.RUnlock()

	if exists && time.Since(idx.buildTime) < isrcIndexTTL {
		return idx
	}

	// Use per-directory mutex to prevent multiple goroutines from building simultaneously
	buildLock, _ := isrcBuildingMu.LoadOrStore(outputDir, &sync.Mutex{})
	mu := buildLock.(*sync.Mutex)
	mu.Lock()
	defer mu.Unlock()

	// Double-check cache after acquiring lock (another goroutine may have built it)
	isrcIndexCacheMu.RLock()
	idx, exists = isrcIndexCache[outputDir]
	isrcIndexCacheMu.RUnlock()

	if exists && time.Since(idx.buildTime) < isrcIndexTTL {
		return idx
	}

	return buildISRCIndex(outputDir)
}

func buildISRCIndex(outputDir string) *ISRCIndex {
	idx := &ISRCIndex{
		index:     make(map[string]string),
		outputDir: outputDir,
		buildTime: time.Now(),
	}

	if outputDir == "" {
		return idx
	}

	startTime := time.Now()
	fileCount := 0

	filepath.Walk(outputDir, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return nil
		}

		ext := strings.ToLower(filepath.Ext(path))
		if ext != ".flac" {
			return nil
		}

		metadata, err := ReadMetadata(path)
		if err != nil || metadata.ISRC == "" {
			return nil
		}

		idx.index[strings.ToUpper(metadata.ISRC)] = path
		fileCount++
		return nil
	})

	fmt.Printf("[ISRCIndex] Built index for %s: %d files in %v\n",
		outputDir, fileCount, time.Since(startTime).Round(time.Millisecond))

	isrcIndexCacheMu.Lock()
	isrcIndexCache[outputDir] = idx
	isrcIndexCacheMu.Unlock()

	return idx
}

func (idx *ISRCIndex) lookup(isrc string) (string, bool) {
	if isrc == "" {
		return "", false
	}

	idx.mu.RLock()
	defer idx.mu.RUnlock()

	path, exists := idx.index[strings.ToUpper(isrc)]
	return path, exists
}

func (idx *ISRCIndex) remove(isrc string) {
	if isrc == "" {
		return
	}

	idx.mu.Lock()
	defer idx.mu.Unlock()

	delete(idx.index, strings.ToUpper(isrc))
}

func (idx *ISRCIndex) Lookup(isrc string) (string, error) {
	path, _ := idx.lookup(isrc)
	return path, nil
}

func (idx *ISRCIndex) Add(isrc, filePath string) {
	if isrc == "" || filePath == "" {
		return
	}

	idx.mu.Lock()
	defer idx.mu.Unlock()

	idx.index[strings.ToUpper(isrc)] = filePath
}

func InvalidateISRCCache(outputDir string) {
	isrcIndexCacheMu.Lock()
	delete(isrcIndexCache, outputDir)
	isrcIndexCacheMu.Unlock()
}

func checkISRCExistsInternal(outputDir, isrc string) (string, bool) {
	if isrc == "" || outputDir == "" {
		return "", false
	}

	idx := GetISRCIndex(outputDir)
	filePath, exists := idx.lookup(isrc)
	if !exists {
		return "", false
	}

	if !CheckFileExists(filePath) {
		// Stale index entry; remove it and return not found.
		idx.remove(isrc)
		return "", false
	}

	return filePath, true
}

func CheckISRCExists(outputDir, isrc string) (string, error) {
	filepath, _ := checkISRCExistsInternal(outputDir, isrc)
	return filepath, nil
}

func CheckFileExists(filePath string) bool {
	info, err := os.Stat(filePath)
	if err != nil {
		return false
	}
	return !info.IsDir() && info.Size() > 0
}

type FileExistenceResult struct {
	ISRC       string `json:"isrc"`
	Exists     bool   `json:"exists"`
	FilePath   string `json:"file_path,omitempty"`
	TrackName  string `json:"track_name,omitempty"`
	ArtistName string `json:"artist_name,omitempty"`
}

func CheckFilesExistParallel(outputDir string, tracksJSON string) (string, error) {
	var tracks []struct {
		ISRC       string `json:"isrc"`
		TrackName  string `json:"track_name"`
		ArtistName string `json:"artist_name"`
	}
	if err := json.Unmarshal([]byte(tracksJSON), &tracks); err != nil {
		return "", fmt.Errorf("failed to parse tracks JSON: %w", err)
	}

	results := make([]FileExistenceResult, len(tracks))

	isrcIdx := GetISRCIndex(outputDir)

	var wg sync.WaitGroup
	for i, track := range tracks {
		wg.Add(1)
		go func(resultIdx int, t struct {
			ISRC       string `json:"isrc"`
			TrackName  string `json:"track_name"`
			ArtistName string `json:"artist_name"`
		}) {
			defer wg.Done()

			result := FileExistenceResult{
				ISRC:       t.ISRC,
				TrackName:  t.TrackName,
				ArtistName: t.ArtistName,
				Exists:     false,
			}

			if t.ISRC != "" {
				if filePath, exists := isrcIdx.lookup(t.ISRC); exists {
					result.Exists = true
					result.FilePath = filePath
				}
			}

			results[resultIdx] = result
		}(i, track)
	}

	wg.Wait()

	resultJSON, err := json.Marshal(results)
	if err != nil {
		return "", fmt.Errorf("failed to marshal results: %w", err)
	}

	return string(resultJSON), nil
}

func PreBuildISRCIndex(outputDir string) error {
	if outputDir == "" {
		return fmt.Errorf("output directory is required")
	}

	buildISRCIndex(outputDir)
	return nil
}

func AddToISRCIndex(outputDir, isrc, filePath string) {
	if outputDir == "" || isrc == "" || filePath == "" {
		return
	}

	isrcIndexCacheMu.RLock()
	idx, exists := isrcIndexCache[outputDir]
	isrcIndexCacheMu.RUnlock()

	if exists {
		idx.Add(isrc, filePath)
	}
}
