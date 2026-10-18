package main

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/jackc/pgx/v5"
)

func ts(v interface{}) string {
	if t, ok := v.(time.Time); ok {
		return t.Local().Format("02.01 15:04:05")
	}
	return "-"
}

func dur(ended, started interface{}) string {
	e, ok1 := ended.(time.Time)
	s, ok2 := started.(time.Time)
	if !ok1 || !ok2 {
		return "ACIK"
	}
	return fmt.Sprintf("%.0fs", e.Sub(s).Seconds())
}

func dash(s string) string {
	if s == "" {
		return "-"
	}
	return s
}

func main() {
	dsn := os.Getenv("SEGNOX_DB_URL")
	if dsn == "" {
		fmt.Println("SEGNOX_DB_URL yok")
		os.Exit(1)
	}
	ctx := context.Background()
	c, err := pgx.Connect(ctx, dsn)
	if err != nil {
		fmt.Println("baglanti hatasi:", err)
		os.Exit(1)
	}
	defer c.Close(ctx)

	fmt.Println("=== OTURUMLAR ===")
	fmt.Printf("%-16s %-8s %-8s %-9s %-7s %10s\n", "baslangic", "rol", "sure", "yol", "fps", "bayt")
	rows, _ := c.Query(ctx, `
		SELECT s.started_at, s.role, s.ended_at, s.end_reason,
		       s.candidate_type, s.bytes_sent, s.avg_fps
		FROM support_sessions s ORDER BY s.started_at DESC LIMIT 12`)
	n := 0
	for rows.Next() {
		var started, ended interface{}
		var role, reason, cand string
		var bytes int64
		var fps float32
		if rows.Scan(&started, &role, &ended, &reason, &cand, &bytes, &fps) == nil {
			n++
			fmt.Printf("%-16s %-8s %-8s %-9s %-7.1f %10d\n",
				ts(started), role, dur(ended, started), dash(cand), fps, bytes)
		}
	}
	rows.Close()
	if n == 0 {
		fmt.Println("(kayit yok)")
	}

	var open int
	_ = c.QueryRow(ctx, `SELECT count(*) FROM support_sessions WHERE ended_at IS NULL`).Scan(&open)
	fmt.Println("\nacik oturum:", open)

	fmt.Println("\n=== SON ISLEMLER ===")
	ar, _ := c.Query(ctx, `SELECT at, actor_type, action, target, ip FROM audit_log ORDER BY at DESC LIMIT 10`)
	for ar.Next() {
		var at interface{}
		var at2, act, tgt, ip string
		if ar.Scan(&at, &at2, &act, &tgt, &ip) == nil {
			fmt.Printf("%-16s %-8s %-24s %-16s %s\n", ts(at), at2, act, tgt, ip)
		}
	}
	ar.Close()

	fmt.Println("\n=== KULLANICILAR ===")
	ur, _ := c.Query(ctx, `SELECT email, role FROM users ORDER BY email`)
	for ur.Next() {
		var e, r string
		if ur.Scan(&e, &r) == nil {
			fmt.Printf("%-28s %s\n", e, r)
		}
	}
	ur.Close()
}