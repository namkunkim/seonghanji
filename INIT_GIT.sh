#!/usr/bin/env bash
# GitHub 초기 push 스크립트
# 사용법: GitHub에서 빈 private 저장소 seonghanji 를 만든 뒤 실행

set -e

read -p "GitHub 사용자명: " GH_USER

git init
git add .
git commit -m "docs: initial design documents

SEONGHANJI: MANDATE 기획 문서 25종
- 세계관: 성계 19 · 권역 45 · 회랑 15
- 인물: 명장 150 · 일반 무장 256 · 이역 90
- 시스템: 전투 5페이즈 · 부분 점령 · 외교 · 시간/수익
- 캠페인: 시나리오 6종 Timeline · 세계 상태 4형 · 기능 이벤트 40
- 서사: 프롤로그 · 엔딩 후일담 10종
- 기술: AI 설계 · UI 설계"

git branch -M main
git remote add origin "https://github.com/${GH_USER}/seonghanji.git"
git push -u origin main

echo ""
echo "완료. https://github.com/${GH_USER}/seonghanji"
