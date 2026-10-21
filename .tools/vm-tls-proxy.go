// Segnox VM testi icin TLS sonlandirici reverse proxy.
//
// Neden: ajan, loopback disindaki sunucu icin duz HTTP'i reddeder
// (K-21: "https required for a non-loopback server"). Test sunucusu
// NAT adresinde (192.168.79.1) calistigi icin araya TLS giren bir proxy
// koyuyoruz: konuk, kendi guvendigi kok sertifikayi yukleyerek ajanin
// https:// ile baglanmasini sagliyor.
//
// Kullanim:
//   go run vm-tls-proxy.go -listen 8443 -target 127.0.0.1:8080 -ip 192.168.79.1 -dir <klasor>
//
// Uretilen dosyalar:
//   ca.pem / ca.der  -> kok sertifika (konuga kurulur)
//   server.pem       -> yaprak sertifika + anahtar (proxy kullanir)

package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"flag"
	"fmt"
	"log"
	"math/big"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"path/filepath"
	"time"
)

func main() {
	listen := flag.String("listen", "8443", "dinlenecek port")
	target := flag.String("target", "127.0.0.1:8080", "arkadaki sunucu")
	ip := flag.String("ip", "192.168.79.1", "sertifikaya eklenecek IP")
	dir := flag.String("dir", "", "sertifika klasoru")
	flag.Parse()

	if *dir == "" {
		*dir = "cert"
	}
	if err := os.MkdirAll(*dir, 0o750); err != nil {
		log.Fatal(err)
	}

	certFile := filepath.Join(*dir, "server.pem")

	if _, err := os.Stat(certFile); err != nil {
		if err := uret(*dir, *ip); err != nil {
			log.Fatal(err)
		}
	}

	cert, err := tls.LoadX509KeyPair(certFile, certFile)
	if err != nil {
		log.Fatalf("sertifika yuklenemedi: %v", err)
	}

	tu, err := url.Parse("http://" + *target)
	if err != nil {
		log.Fatal(err)
	}
	proxy := httputil.NewSingleHostReverseProxy(tu)
	proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, e error) {
		log.Printf("proxy hatasi: %v", e)
		http.Error(w, "proxy hatasi", http.StatusBadGateway)
	}

	srv := &http.Server{
		Addr:      ":" + *listen,
		Handler:   proxy,
		TLSConfig: &tls.Config{Certificates: []tls.Certificate{cert}, MinVersion: tls.VersionTLS12},
	}
	ln, err := net.Listen("tcp", srv.Addr)
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("TLS proxy: https://0.0.0.0:%s -> %s", *listen, *target)
	log.Printf("kok sertifika: %s (konuga kurulacak)", filepath.Join(*dir, "ca.pem"))
	if err := srv.ServeTLS(ln, "", ""); err != nil {
		log.Fatal(err)
	}
}

// uret CA + yaprak sertifika uretir.
func uret(dir, ipStr string) error {
	caKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return err
	}
	caTpl := &x509.Certificate{
		SerialNumber:          big.NewInt(time.Now().UnixNano()),
		Subject:               pkix.Name{CommonName: "Segnox VM Test CA", Organization: []string{"Segnox Test"}},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().Add(365 * 24 * time.Hour),
		IsCA:                  true,
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageCRLSign | x509.KeyUsageDigitalSignature,
		BasicConstraintsValid: true,
	}
	caDER, err := x509.CreateCertificate(rand.Reader, caTpl, caTpl, &caKey.PublicKey, caKey)
	if err != nil {
		return err
	}
	caCert, err := x509.ParseCertificate(caDER)
	if err != nil {
		return err
	}

	leafKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return err
	}
	ipAddr := net.ParseIP(ipStr)
	if ipAddr == nil {
		return fmt.Errorf("gecersiz IP: %s", ipStr)
	}
	leafTpl := &x509.Certificate{
		SerialNumber: big.NewInt(time.Now().UnixNano() + 1),
		Subject:      pkix.Name{CommonName: "segnox-vm-test"},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(365 * 24 * time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		IPAddresses:  []net.IP{ipAddr, net.ParseIP("127.0.0.1")},
		DNSNames:     []string{"localhost", "segnox-vm-test"},
	}
	leafDER, err := x509.CreateCertificate(rand.Reader, leafTpl, caCert, &leafKey.PublicKey, caKey)
	if err != nil {
		return err
	}

	// ca.pem + ca.der
	caPEMBytes := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: caDER})
	if err := os.WriteFile(filepath.Join(dir, "ca.pem"), caPEMBytes, 0o644); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(dir, "ca.der"), caDER, 0o644); err != nil {
		return err
	}

	// server.pem: yaprak + anahtar
	leafKeyDER, err := x509.MarshalECPrivateKey(leafKey)
	if err != nil {
		return err
	}
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: leafKeyDER})
	leafPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: leafDER})
	if err := os.WriteFile(filepath.Join(dir, "server.pem"), append(leafPEM, keyPEM...), 0o600); err != nil {
		return err
	}
	fmt.Println("sertifikalar uretildi:", dir)
	return nil
}
