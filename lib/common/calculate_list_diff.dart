/// 计算去除 LCS 之后的最大差异，即为不匹配度
/// LCS：最长公共子序列，两字符串中，顺序一致但无需连续的最长子序列
/// 例如 answer="ABCDEFGHIJ", submit="CDXEFGHYW"
/// LCS="CDEFGH"
///
int calculateMismatch({required String answer, required String submit}) {
  int m = answer.length;
  int n = submit.length;

  // 处理空字符串的情况
  if (m == 0 || n == 0) {
    return m > n ? m : n;
  }

  // 初始化二维DP数组
  List<List<int>> dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));

  // 填充DP表
  for (int i = 1; i <= m; i++) {
    for (int j = 1; j <= n; j++) {
      if (answer[i - 1] == submit[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1] + 1;
      } else {
        dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
      }
    }
  }

  // 获取LCS长度
  int lcsLength = dp[m][n];

  // 计算剩余字符长度
  int answerRemaining = m - lcsLength;
  int submitRemaining = n - lcsLength;

  // 返回较大的剩余长度
  return answerRemaining > submitRemaining ? answerRemaining : submitRemaining;
}
