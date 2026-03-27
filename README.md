<p align="center">
  <h1 align="center">S3 Dart</h1>
</p>

An S3 Dart Client SDK that provides simple APIs to access any Amazon S3 compatible object storage server. Optimized for [Wasabi S3](https://wasabi.com) but fully compatible with AWS S3, MinIO, Filebase, and any other S3-compatible provider.

<p align="center">
  <a href="https://github.com/markhorrocks/minio-dart/actions/workflows/dart.yml">
    <img src="https://github.com/markhorrocks/minio-dart/workflows/Dart/badge.svg">
  </a>
  <a href="https://pub.dev/packages/s3_dart">
    <img src="https://img.shields.io/pub/v/s3_dart">
  </a>
</p>


## Features

- **Custom endpoint support** — returns your supplied endpoint directly, no hardcoded AWS region overrides
- **Smart region detection** — skips the `getBucketRegion` API call when the region is already present in the endpoint URL
- **File operations for all providers** — `fPutObject` / `fGetObject` work correctly with any S3-compatible endpoint, not just AWS
- **Presigned DELETE** — `presignedDeleteObject` convenience method for generating signed delete URLs
- **Region fallback** — gracefully falls back to `us-east-1` or the configured region instead of failing with an empty string


## API

| Bucket operations       | Object operations        | Presigned operations      | Bucket Policy & Notification operations |
| ----------------------- | ------------------------ | ------------------------- | --------------------------------------- |
| [makeBucket]            | [getObject]              | [presignedUrl]            | [getBucketNotification]                 |
| [listBuckets]           | [getPartialObject]       | [presignedGetObject]      | [setBucketNotification]                 |
| [bucketExists]          | [fGetObject]             | [presignedPutObject]      | [removeAllBucketNotification]           |
| [removeBucket]          | [putObject]              | [presignedDeleteObject]   | [listenBucketNotification]              |
| [listObjects]           | [fPutObject]             | [presignedPostPolicy]     | [getBucketPolicy]                       |
| [listObjectsV2]         | [copyObject]             |                           | [setBucketPolicy]                       |
| [listIncompleteUploads] | [statObject]             |                           |                                         |
| [listAllObjects]        | [removeObject]           |                           |                                         |
| [listAllObjectsV2]      | [removeObjects]          |                           |                                         |
|                         | [removeIncompleteUpload] |                           |                                         |


## Usage

### Initialize S3 Client

**Wasabi S3**

Wasabi S3 uses regional endpoints. Specify the endpoint that matches your bucket's region:

```dart
// US East 1 (default)
final minio = Minio(
  endPoint: 's3.wasabisys.com',
  accessKey: 'YOUR-ACCESSKEYID',
  secretKey: 'YOUR-SECRETACCESSKEY',
  region: 'us-east-1',
);

// US East 2
final minio = Minio(
  endPoint: 's3.us-east-2.wasabisys.com',
  accessKey: 'YOUR-ACCESSKEYID',
  secretKey: 'YOUR-SECRETACCESSKEY',
  region: 'us-east-2',
);

// US West 1
final minio = Minio(
  endPoint: 's3.us-west-1.wasabisys.com',
  accessKey: 'YOUR-ACCESSKEYID',
  secretKey: 'YOUR-SECRETACCESSKEY',
  region: 'us-west-1',
);

// EU Central 1
final minio = Minio(
  endPoint: 's3.eu-central-1.wasabisys.com',
  accessKey: 'YOUR-ACCESSKEYID',
  secretKey: 'YOUR-SECRETACCESSKEY',
  region: 'eu-central-1',
);

// AP Southeast 2 (Sydney)
final minio = Minio(
  endPoint: 's3.ap-southeast-2.wasabisys.com',
  accessKey: 'YOUR-ACCESSKEYID',
  secretKey: 'YOUR-SECRETACCESSKEY',
  region: 'ap-southeast-2',
);
```

All Wasabi regional endpoints follow the pattern `s3.<region>.wasabisys.com`.
See [Wasabi service endpoints](https://docs.wasabi.com/docs/wasabi-service-endpoints) for the full list.

---

**AWS S3**

```dart
final minio = Minio(
  endPoint: 's3.amazonaws.com',
  accessKey: 'YOUR-ACCESSKEYID',
  secretKey: 'YOUR-SECRETACCESSKEY',
);
```

**MinIO**

```dart
final minio = Minio(
  endPoint: 'play.min.io',
  accessKey: 'Q3AM3UQ867SPQQA43P2F',
  secretKey: 'zuf+tfteSlswRu7BJ86wekitnifILbZam1KYY3TG',
);
```

**Filebase**

```dart
final minio = Minio(
  endPoint: 's3.filebase.com',
  accessKey: 'YOUR-ACCESSKEYID',
  secretKey: 'YOUR-SECRETACCESSKEY',
  useSSL: true,
);
```

---

### File upload

```dart
import 'package:s3_dart/io.dart';
import 'package:s3_dart/minio.dart';

void main() async {
  final minio = Minio(
    endPoint: 's3.wasabisys.com',
    accessKey: 'YOUR-ACCESSKEYID',
    secretKey: 'YOUR-SECRETACCESSKEY',
  );

  await minio.fPutObject('mybucket', 'myobject', 'path/to/file');
}
```

> To use `fPutObject()` and `fGetObject()`, you must `import 'package:s3_dart/io.dart';`

For a complete example, see: [example]

### Upload with progress

```dart
import 'package:s3_dart/minio.dart';

void main() async {
  final minio = Minio(
    endPoint: 's3.wasabisys.com',
    accessKey: 'YOUR-ACCESSKEYID',
    secretKey: 'YOUR-SECRETACCESSKEY',
  );

  await minio.putObject(
    'mybucket',
    'myobject',
    Stream<Uint8List>.value(Uint8List(1024)),
    onProgress: (bytes) => print('$bytes uploaded'),
  );
}
```

### Get object

```dart
import 'dart:io';
import 'package:s3_dart/minio.dart';

void main() async {
  final minio = Minio(
    endPoint: 's3.wasabisys.com',
    accessKey: 'YOUR-ACCESSKEYID',
    secretKey: 'YOUR-SECRETACCESSKEY',
  );

  final stream = await minio.getObject('mybucket', 'myobject');

  // Get object length
  print(stream.contentLength);

  // Write object data to file
  await stream.pipe(File('output.txt').openWrite());
}
```

---

## Presigned URLs

Presigned URLs allow clients to perform S3 operations directly — without exposing credentials. This SDK supports presigned GET, PUT, DELETE, and HEAD via both named convenience methods and the generic `presignedUrl`.

### Presigned GET (download)

```dart
final url = await minio.presignedGetObject(
  'mybucket',
  'myobject',
  expires: 3600, // 1 hour
);
// Share this URL — anyone can download the object until it expires
```

### Presigned PUT (upload)

```dart
final url = await minio.presignedPutObject(
  'mybucket',
  'myobject',
  expires: 900, // 15 minutes
);
// The client can PUT directly to this URL without credentials
```

### Presigned DELETE (remove object)

```dart
final url = await minio.presignedDeleteObject(
  'mybucket',
  'myobject',
  expires: 900, // 15 minutes
);
// Send an HTTP DELETE request to this URL to remove the object
```

### Generic presigned URL

Use `presignedUrl` for any HTTP method (GET, PUT, DELETE, HEAD):

```dart
final url = await minio.presignedUrl(
  'DELETE',
  'mybucket',
  'myobject',
  expires: 900,
);
```

### Presigned POST policy (browser upload)

For browser uploads with policy restrictions on name, content-type, size, and expiry:

```dart
final policy = PostPolicy()
  ..setBucket('mybucket')
  ..setKey('myobject')
  ..setExpires(DateTime.now().add(Duration(minutes: 15)));

final formData = await minio.presignedPostPolicy(policy);
```

---

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

Contributions are welcome.

## License

MIT

[tracker]: https://github.com/markhorrocks/minio-dart/issues
[example]: https://pub.dev/packages/minio#-example-tab-

[makeBucket]: https://pub.dev/documentation/minio/latest/minio/Minio/makeBucket.html
[listBuckets]: https://pub.dev/documentation/minio/latest/minio/Minio/listBuckets.html
[bucketExists]: https://pub.dev/documentation/minio/latest/minio/Minio/bucketExists.html
[removeBucket]: https://pub.dev/documentation/minio/latest/minio/Minio/removeBucket.html
[listObjects]: https://pub.dev/documentation/minio/latest/minio/Minio/listObjects.html
[listObjectsV2]: https://pub.dev/documentation/minio/latest/minio/Minio/listObjectsV2.html
[listIncompleteUploads]: https://pub.dev/documentation/minio/latest/minio/Minio/listIncompleteUploads.html
[listAllObjects]: https://pub.dev/documentation/minio/latest/minio/Minio/listAllObjects.html
[listAllObjectsV2]: https://pub.dev/documentation/minio/latest/minio/Minio/listAllObjectsV2.html

[getObject]: https://pub.dev/documentation/minio/latest/minio/Minio/getObject.html
[getPartialObject]: https://pub.dev/documentation/minio/latest/minio/Minio/getPartialObject.html
[putObject]: https://pub.dev/documentation/minio/latest/minio/Minio/putObject.html
[copyObject]: https://pub.dev/documentation/minio/latest/minio/Minio/copyObject.html
[statObject]: https://pub.dev/documentation/minio/latest/minio/Minio/statObject.html
[removeObject]: https://pub.dev/documentation/minio/latest/minio/Minio/removeObject.html
[removeObjects]: https://pub.dev/documentation/minio/latest/minio/Minio/removeObjects.html
[removeIncompleteUpload]: https://pub.dev/documentation/minio/latest/minio/Minio/removeIncompleteUpload.html

[fGetObject]: https://pub.dev/documentation/minio/latest/io/MinioX/fGetObject.html
[fPutObject]: https://pub.dev/documentation/minio/latest/io/MinioX/fPutObject.html

[presignedUrl]: https://pub.dev/documentation/minio/latest/minio/Minio/presignedUrl.html
[presignedGetObject]: https://pub.dev/documentation/minio/latest/minio/Minio/presignedGetObject.html
[presignedPutObject]: https://pub.dev/documentation/minio/latest/minio/Minio/presignedPutObject.html
[presignedDeleteObject]: https://pub.dev/documentation/minio/latest/minio/Minio/presignedDeleteObject.html
[presignedPostPolicy]: https://pub.dev/documentation/minio/latest/minio/Minio/presignedPostPolicy.html

[getBucketNotification]: https://pub.dev/documentation/minio/latest/minio/Minio/getBucketNotification.html
[setBucketNotification]: https://pub.dev/documentation/minio/latest/minio/Minio/setBucketNotification.html
[removeAllBucketNotification]: https://pub.dev/documentation/minio/latest/minio/Minio/removeAllBucketNotification.html
[listenBucketNotification]: https://pub.dev/documentation/minio/latest/minio/Minio/listenBucketNotification.html

[getBucketPolicy]: https://pub.dev/documentation/minio/latest/minio/Minio/getBucketPolicy.html
[setBucketPolicy]: https://pub.dev/documentation/minio/latest/minio/Minio/setBucketPolicy.html
