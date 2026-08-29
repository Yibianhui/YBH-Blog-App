import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/blog_api.dart';

/// 文章卡片（列表与搜索结果共用）。
class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.post, this.onTap});

  final PostSummary post;
  final VoidCallback? onTap;

  static String formatDate(DateTime? date) {
    if (date == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              height: 112,
              child: CachedNetworkImage(
                imageUrl: post.coverUrl,
                fit: BoxFit.cover,
                memCacheWidth: 448,
                placeholder: (context, url) => const CoverPlaceholder(),
                errorWidget: (context, url, error) => const CoverPlaceholder(),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, height: 1.35),
                    ),
                    if (post.excerpt.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        post.excerpt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant, height: 1.45),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.schedule_outlined, size: 13, color: colorScheme.outline),
                        const SizedBox(width: 4),
                        Text(
                          formatDate(post.date),
                          style: TextStyle(fontSize: 11.5, color: colorScheme.outline),
                        ),
                        const SizedBox(width: 8),
                        if (post.terms.isNotEmpty)
                          Expanded(
                            child: Text(
                              post.terms.take(2).join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, color: colorScheme.primary),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 封面占位（渐变 + 图标）。
class CoverPlaceholder extends StatelessWidget {
  const CoverPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.75),
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.45),
          ],
        ),
      ),
      child: const Center(
        child: Icon(Icons.article_outlined, color: Colors.white70, size: 30),
      ),
    );
  }
}
