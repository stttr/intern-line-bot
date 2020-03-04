class TmdbGenre
  # from by
  # https://api.themoviedb.org/3/genre/movie/list?api_key=dcab2f241020c5bf67097428d0fddca1&language=ja
  GENRES = {
    "アクション"=> 28,
    "アドベンチャー"=> 12,
    "アニメーション"=> 16,
    "コメディ"=> 35,
    "犯罪"=> 80,
    "ドキュメンタリー"=> 99,
    "ドラマ"=> 18,
    "ファミリー"=> 10751,
    "ファンタジー"=> 14,
    "履歴"=> 36,
    "ホラー"=> 27,
    "音楽"=> 10402,
    "謎"=> 9648,
    "ロマンス"=> 10749,
    "サイエンスフィクション"=> 878,
    "テレビ映画"=> 10770,
    "スリラー"=> 53,
    "戦争"=> 10752,
    "西洋"=> 37
  }

  def self.find_id_by_name(name)
    GENRES[name]
  end
end
