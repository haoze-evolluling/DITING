package tunnel

import (
	"encoding/binary"
	"fmt"
	"os"
	"strings"

	"golang.org/x/sys/unix"
)

const (
	dtriMagic      = 0x44545249
	dtriVersion    = 1
	dtriHeaderSize = 36
	dtriNodeSize   = 12
	dtriEdgeSize   = 12
)

type dtriReader struct {
	file         *os.File
	data         []byte
	filePath     string
	modTime      int64
	size         int64
	nodes        int
	edges        int
	sources      int
	bloomBits    int
	bloomBytes   int
	nodeOffset   int
	edgeOffset   int
	labelOffset  int
	sourceOffset int
	sourceNames  []string
	bloom        []byte
}

func openDTRI(path string) (*dtriReader, error) {
	if path == "" {
		return nil, fmt.Errorf("empty path")
	}

	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("failed to open DTRI file %s: %w", path, err)
	}

	stat, err := f.Stat()
	if err != nil {
		f.Close()
		return nil, fmt.Errorf("failed to stat DTRI file %s: %w", path, err)
	}

	size := stat.Size()
	if size < dtriHeaderSize {
		f.Close()
		return nil, fmt.Errorf("file %s too small to be a valid DTRI", path)
	}

	data, err := unix.Mmap(int(f.Fd()), 0, int(size), unix.PROT_READ, unix.MAP_SHARED)
	if err != nil {
		f.Close()
		return nil, fmt.Errorf("mmap failed for %s: %w", path, err)
	}

	magic := binary.BigEndian.Uint32(data[0:4])
	if magic != dtriMagic {
		unix.Munmap(data)
		f.Close()
		return nil, fmt.Errorf("invalid DTRI magic: expected %X, got %X", dtriMagic, magic)
	}

	version := binary.BigEndian.Uint32(data[4:8])
	if version != dtriVersion {
		unix.Munmap(data)
		f.Close()
		return nil, fmt.Errorf("invalid DTRI version: expected %d, got %d", dtriVersion, version)
	}

	nodes := int(binary.BigEndian.Uint32(data[8:12]))
	edges := int(binary.BigEndian.Uint32(data[12:16]))
	sources := int(binary.BigEndian.Uint32(data[16:20]))
	bloomBits := int(binary.BigEndian.Uint32(data[20:24]))
	bloomBytes := int(binary.BigEndian.Uint32(data[24:28]))
	labelsBytes := int(binary.BigEndian.Uint32(data[28:32]))
	sourcesBytes := int(binary.BigEndian.Uint32(data[32:36]))

	nodeOffset := dtriHeaderSize + bloomBytes
	edgeOffset := nodeOffset + nodes*dtriNodeSize
	labelOffset := edgeOffset + edges*dtriEdgeSize
	sourceOffset := labelOffset + labelsBytes

	if sourceOffset+sourcesBytes > len(data) {
		unix.Munmap(data)
		f.Close()
		return nil, fmt.Errorf("corrupted DTRI file %s", path)
	}

	sourceNames := make([]string, sources)
	cursor := sourceOffset
	for i := 0; i < sources; i++ {
		if cursor+4 > len(data) {
			break
		}
		strLen := int(binary.BigEndian.Uint32(data[cursor : cursor+4]))
		cursor += 4
		if cursor+strLen > len(data) {
			break
		}
		sourceNames[i] = string(data[cursor : cursor+strLen])
		cursor += strLen
	}

	modTime := stat.ModTime().UnixNano()

	return &dtriReader{
		file:         f,
		data:         data,
		filePath:     path,
		modTime:      modTime,
		size:         size,
		nodes:        nodes,
		edges:        edges,
		sources:      sources,
		bloomBits:    bloomBits,
		bloomBytes:   bloomBytes,
		nodeOffset:   nodeOffset,
		edgeOffset:   edgeOffset,
		labelOffset:  labelOffset,
		sourceOffset: sourceOffset,
		sourceNames:  sourceNames,
		bloom:        data[dtriHeaderSize : dtriHeaderSize+bloomBytes],
	}, nil
}

func (r *dtriReader) close() {
	if r == nil {
		return
	}
	if r.data != nil {
		_ = unix.Munmap(r.data)
		r.data = nil
	}
	if r.file != nil {
		_ = r.file.Close()
		r.file = nil
	}
}

func (r *dtriReader) compareEdge(edgeIndex int, domain string, start, end int) int {
	base := r.edgeOffset + edgeIndex*dtriEdgeSize
	offset := int(binary.BigEndian.Uint32(r.data[base : base+4]))
	length := int(binary.BigEndian.Uint32(r.data[base+4 : base+8]))
	targetLen := end - start
	minLen := targetLen
	if length < minLen {
		minLen = length
	}
	labelBase := r.labelOffset + offset
	for i := 0; i < minLen; i++ {
		cTarget := int(domain[start+i])
		cEdge := int(r.data[labelBase+i])
		if cTarget != cEdge {
			return cTarget - cEdge
		}
	}
	return targetLen - length
}

func (r *dtriReader) findChild(node int, domain string, start, end int) int {
	base := r.nodeOffset + node*dtriNodeSize
	first := int(binary.BigEndian.Uint32(r.data[base+4 : base+8]))
	count := int(binary.BigEndian.Uint32(r.data[base+8 : base+12]))
	low := first
	high := first + count - 1
	for low <= high {
		mid := int(uint(low+high) >> 1)
		cmp := r.compareEdge(mid, domain, start, end)
		if cmp < 0 {
			high = mid - 1
		} else if cmp > 0 {
			low = mid + 1
		} else {
			edgeBase := r.edgeOffset + mid*dtriEdgeSize
			return int(binary.BigEndian.Uint32(r.data[edgeBase+8 : edgeBase+12]))
		}
	}
	return -1
}

func dtriHashes(val string, start, end int) (int64, int64) {
	h1 := int64(-3750763034362895579)
	h2 := int64(-3750763034362895579)
	for i := start; i < end; i++ {
		b := int64(val[i]) & 0xff
		h1 = (h1 ^ b) * 1099511628211
		h2 = (h2 * 1099511628211) ^ b
	}
	return h1, h2 | 1
}

func (r *dtriReader) mightContainDomainOrParent(domain string) bool {
	if r.bloomBits <= 0 || len(r.bloom) == 0 {
		return true
	}
	mod := int64(r.bloomBits)
	start := 0
	for start < len(domain) {
		h1, h2 := dtriHashes(domain, start, len(domain))
		possible := true
		for i := 0; i < 7; i++ {
			sum := h1 + int64(i)*h2
			bit := int((sum%mod + mod) % mod)
			byteIdx := bit / 8
			if byteIdx >= len(r.bloom) || (r.bloom[byteIdx]&(1<<uint(bit%8))) == 0 {
				possible = false
				break
			}
		}
		if possible {
			return true
		}
		dot := strings.IndexByte(domain[start:], '.')
		if dot < 0 {
			break
		}
		start += dot + 1
	}
	return false
}

func (r *dtriReader) containsOrParent(domain string) (bool, string) {
	return r.containsOrParentWithDisabled(domain, nil)
}

func (r *dtriReader) containsOrParentWithDisabled(domain string, disabled map[string]struct{}) (bool, string) {
	if r == nil || len(r.data) == 0 {
		return false, ""
	}
	domain = strings.TrimSuffix(strings.ToLower(domain), ".")
	if domain == "" || !r.mightContainDomainOrParent(domain) {
		return false, ""
	}
	node := 0
	end := len(domain)
	for end > 0 {
		dot := strings.LastIndexByte(domain[:end], '.')
		start := dot + 1
		child := r.findChild(node, domain, start, end)
		if child < 0 {
			return false, ""
		}
		node = child
		pattern := domain[start:]
		if disabled != nil {
			if _, isOff := disabled[pattern]; isOff {
				end = dot
				continue
			}
		}
		base := r.nodeOffset + node*dtriNodeSize
		sourceIdx := int(int32(binary.BigEndian.Uint32(r.data[base : base+4])))
		if sourceIdx >= 0 {
			sourceName := "filter_list"
			if sourceIdx < len(r.sourceNames) {
				sourceName = r.sourceNames[sourceIdx]
			}
			return true, sourceName
		}
		end = dot
	}
	return false, ""
}
