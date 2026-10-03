// packet_pipe_test.go validates the pooled packet pipe: data integrity across
// the pool/queue/consumer ownership handoffs, the pooled size-class boundary,
// and shutdown unblocking under concurrent producers (race coverage via -race).

package tunnel

import (
	"bytes"
	"io"
	"sync"
	"testing"
)

func TestPacketPipePushReadRoundTrip(t *testing.T) {
	p := newPacketPipe()
	defer p.Close()

	payload := []byte("packet payload bytes")
	p.Push(payload)

	readBuf := make([]byte, len(payload)+16)
	n, err := p.Read(readBuf)
	if err != nil {
		t.Fatalf("Read: %v", err)
	}
	if !bytes.Equal(readBuf[:n], payload) {
		t.Fatalf("round trip mismatch: got %q", readBuf[:n])
	}
}

func TestPacketPipeWritePopRoundTrip(t *testing.T) {
	p := newPacketPipe()
	defer p.Close()

	payload := []byte("outbound packet")
	if _, err := p.Write(payload); err != nil {
		t.Fatalf("Write: %v", err)
	}
	pkt := p.Pop()
	if pkt == nil {
		t.Fatal("Pop returned nil")
	}
	if !bytes.Equal(pkt.b, payload) {
		t.Fatalf("round trip mismatch: got %q", pkt.b)
	}
	pipeBufPut(pkt)
}

func TestPacketPipeOversizedBypassesPool(t *testing.T) {
	p := newPacketPipe()
	defer p.Close()

	payload := make([]byte, pipePooledMaxPacketBytes+1)
	if _, err := p.Write(payload); err != nil {
		t.Fatalf("Write: %v", err)
	}
	pkt := p.Pop()
	if pkt == nil {
		t.Fatal("Pop returned nil")
	}
	if !bytes.Equal(pkt.b, payload) {
		t.Fatal("oversized payload mismatch")
	}
	if cap(pkt.b) <= pipePooledMaxPacketBytes {
		t.Fatalf("oversized buffer unexpectedly within pooled size class (cap=%d)", cap(pkt.b))
	}
	pipeBufPut(pkt)
}

func TestPacketPipeCloseUnblocksRead(t *testing.T) {
	p := newPacketPipe()
	p.Close()

	if _, err := p.Read(make([]byte, defaultTunMTU)); err != io.EOF {
		t.Fatalf("expected io.EOF after close, got %v", err)
	}
	if pkt := p.Pop(); pkt != nil {
		t.Fatalf("expected nil Pop after close, got %d bytes", len(pkt.b))
	}
	if _, err := p.Write([]byte("x")); err != nil {
		t.Fatalf("Write after close must report len without error, got %v", err)
	}
}

func TestPacketPipeConcurrentProducers(t *testing.T) {
	p := newPacketPipe()
	var wg sync.WaitGroup

	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			payload := make([]byte, defaultTunMTU)
			payload[0] = byte(i)
			for j := 0; j < 250; j++ {
				p.Push(payload)
			}
		}(i)
	}

	done := make(chan int, 1)
	go func() {
		buf := make([]byte, defaultTunMTU)
		count := 0
		for {
			if _, err := p.Read(buf); err != nil {
				done <- count
				return
			}
			count++
		}
	}()

	wg.Wait()
	p.Close()
	<-done
}
