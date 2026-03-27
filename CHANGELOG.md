# 1.0.1 

- Add platform support info to pub.dev

# 1.0.0

- Initial release as s3_dart, created by Mark Horrocks
- Fork of xtyxtyx/minio-dart with enhancements for Wasabi S3 and custom S3 endpoints
- Custom S3 endpoint returned directly (no hardcoded AWS region mapping override)
- Smart region detection: skips getBucketRegion API call when region is in the endpoint URL
- Fixed fPutObject / fGetObject for custom (non-AWS) endpoints
- Region fallback: gracefully handles empty region strings
- Added presignedDeleteObject convenience method
