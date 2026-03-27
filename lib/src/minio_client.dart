import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart';
import 'package:s3_dart/minio.dart';
import 'package:s3_dart/src/minio_helpers.dart';
import 'package:s3_dart/src/minio_sign.dart';
import 'package:s3_dart/src/utils.dart';

class MinioRequest extends BaseRequest {
  MinioRequest(super.method, super.url, {this.onProgress});

  dynamic body;
  final void Function(int)? onProgress;

  @override
  ByteStream finalize() {
    super.finalize();

    if (body == null) {
      return const ByteStream(Stream.empty());
    }

    late Stream<Uint8List> stream;

    if (body is Stream<Uint8List>) {
      stream = body;
    } else if (body is String) {
      final data = Utf8Encoder().convert(body);
      headers['content-length'] = data.length.toString();
      stream = Stream<Uint8List>.value(data);
    } else if (body is Uint8List) {
      stream = Stream<Uint8List>.value(body);
      headers['content-length'] = body.length.toString();
    } else {
      throw UnsupportedError(
        'Unsupported body type: ${body.runtimeType}. Supported types are Stream<Uint8List>, String, and Uint8List.',
      );
    }

    if (onProgress == null) {
      return ByteStream(stream);
    }

    var bytesRead = 0;

    stream = stream.transform(MaxChunkSize(1 << 16));

    return ByteStream(
      stream.transform(
        StreamTransformer.fromHandlers(
          handleData: (data, sink) {
            sink.add(data);
            bytesRead += data.length;
            onProgress!(bytesRead);
          },
        ),
      ),
    );
  }

  MinioRequest replace({
    String? method,
    Uri? url,
    Map<String, String>? headers,
    body,
  }) {
    final result = MinioRequest(method ?? this.method, url ?? this.url);
    result.body = body ?? this.body;
    result.headers.addAll(headers ?? this.headers);
    return result;
  }
}

class MinioResponse extends BaseResponse {
  final Uint8List bodyBytes;

  String get body => utf8.decode(bodyBytes);

  MinioResponse.bytes(
    this.bodyBytes,
    int statusCode, {
    BaseRequest? request,
    Map<String, String> headers = const {},
    bool isRedirect = false,
    bool persistentConnection = true,
    String? reasonPhrase,
  }) : super(
          statusCode,
          contentLength: bodyBytes.length,
          request: request,
          headers: headers,
          isRedirect: isRedirect,
          persistentConnection: persistentConnection,
          reasonPhrase: reasonPhrase,
        );

  static Future<MinioResponse> fromStream(StreamedResponse response) async {
    try {
      final body = await response.stream.toBytes();
      return MinioResponse.bytes(
        body,
        response.statusCode,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (e, stackTrace) {
      print('Failed to process response: $e');
      print(stackTrace);
      throw MinioError('Failed to process response: $e');
    }
  }
}

class MinioClient {
  MinioClient(this.minio) {
    anonymous = minio.accessKey.isEmpty && minio.secretKey.isEmpty;
    enableSHA256 = !anonymous && !minio.useSSL;
    port = minio.port;
  }

  final Minio minio;
  final String userAgent = 'MinIO (Unknown; Unknown) minio-dart/3.7.6';

  late bool enableSHA256;
  late bool anonymous;
  late final int port;

  bool endpointContainsRegion(String endPoint, List<String> knownRegions) {
    // Split the endpoint by '.'
    List<String> parts = endPoint.split('.');

    // Check if any part of the endpoint matches a known region
    for (String part in parts) {
      if (knownRegions.contains(part)) {
        return true;
      }
    }

    // If no known region is found in the endpoint
    return false;
  }

  Future<StreamedResponse> _request({
    required String method,
    String? bucket,
    String? object,
    String? region,
    String? resource,
    dynamic payload = '',
    Map<String, dynamic>? queries,
    Map<String, String>? headers,
    void Function(int)? onProgress,
  }) async {
    // Define the list of known regions your service supports
    const List<String> knownRegions = [
      'us-east-1',
      'us-east-2',
      'us-west-1',
      'us-west-2',
      'af-south-1',
      'ap-east-1',
      'ap-south-1',
      'ap-south-2',
      'ap-northeast-1',
      'ap-northeast-2',
      'ap-northeast-3',
      'ap-southeast-1',
      'ap-southeast-2',
      'ap-southeast-3',
      'ca-central-1',
      'eu-central-1',
      'eu-west-1',
      'eu-west-2',
      'eu-west-3',
      'eu-south-1',
      'eu-north-1',
      'eu-central-2',
      'me-south-1',
      'me-central-1',
      'sa-east-1',
    ];

    try {
      // Call getBucketRegion only if region is not provided, bucket is provided, and endpoint does not contain a region
      if (bucket != null &&
          region == null &&
          !endpointContainsRegion(minio.endPoint, knownRegions)) {
        // Get the region of the bucket if it's not explicitly provided
        region = await minio.getBucketRegion(bucket);
      }

      // If region is explicitly provided, or inferred from bucket, and is not part of endpoint, use it in the request
      if (region != null &&
          !endpointContainsRegion(minio.endPoint, knownRegions)) {
      } else {
        // Clear region to avoid duplication if endpoint already contains the region
        region = null;
      }

      // Construct the base request
      final request = getBaseRequest(
        method,
        bucket,
        object,
        minio.endPoint,
        region,
        resource,
        queries,
        headers,
        onProgress,
        minio.useSSL,
        port,
      );

      request.body = payload;

      final date = DateTime.now().toUtc();
      final sha256sum = enableSHA256 ? sha256Hex(payload) : 'UNSIGNED-PAYLOAD';
      request.headers.addAll({
        'user-agent': userAgent,
        'x-amz-date': makeDateLong(date),
        'x-amz-content-sha256': sha256sum,
      });

      try {
        // Ensure the region used for signing matches the request URL and headers
        final authorization = signV4(minio, request, date, region ?? minio.region ?? 'us-east-1');
        request.headers['authorization'] = authorization;
      } catch (e, stackTrace) {
        print('Failed to sign request: $e');
        print(stackTrace);
        throw MinioError('Failed to sign request: $e');
      }

      logRequest(request);

      final response = await request.send();
      return response;
    } catch (e, stackTrace) {
      print('Request failed: $e');
      print(stackTrace);
      throw MinioError('Failed to send request: $e');
    }
  }

  Future<MinioResponse> request({
    required String method,
    String? bucket,
    String? object,
    String? region,
    String? resource,
    dynamic payload = '',
    Map<String, dynamic>? queries,
    Map<String, String>? headers,
    void Function(int)? onProgress,
  }) async {
    final stream = await _request(
      method: method,
      bucket: bucket,
      object: object,
      region: region,
      payload: payload,
      resource: resource,
      queries: queries,
      headers: headers,
      onProgress: onProgress,
    );

    final response = await MinioResponse.fromStream(stream);
    logResponse(response);

    if (response.statusCode >= 400) {
      print('HTTP Error: ${response.statusCode} ${response.reasonPhrase}');
      print('Response Body: ${response.body}');
      throw MinioError(
          'HTTP error: ${response.statusCode} ${response.reasonPhrase}');
    }

    return response;
  }

  Future<StreamedResponse> requestStream({
    required String method,
    String? bucket,
    String? object,
    String? region,
    String? resource,
    dynamic payload = '',
    Map<String, dynamic>? queries,
    Map<String, String>? headers,
  }) async {
    final response = await _request(
      method: method,
      bucket: bucket,
      object: object,
      region: region,
      payload: payload,
      resource: resource,
      queries: queries,
      headers: headers,
    );

    logResponse(response);

    if (response.statusCode >= 400) {
      print('HTTP Error: ${response.statusCode} ${response.reasonPhrase}');
      throw MinioError(
          'HTTP error: ${response.statusCode} ${response.reasonPhrase}');
    }

    return response;
  }

  MinioRequest getBaseRequest(
    String method,
    String? bucket,
    String? object,
    String endPoint,
    String? region,
    String? resource,
    Map<String, dynamic>? queries,
    Map<String, String>? headers,
    void Function(int)? onProgress,
    bool useSSL,
    int? port,
  ) {
    // Generate the URL using user-supplied values
    final url = getRequestUrl(
      endPoint: endPoint,
      region: region,
      bucket: bucket,
      object: object,
      resource: resource,
      queries: queries,
      useSSL: useSSL,
      port: port,
    );

    // Initialize the MinioRequest with the generated URL and method
    final request = MinioRequest(method, url, onProgress: onProgress);

    // Add the host header (important for signature validation)
    request.headers['host'] =
        url.host; // Ensure this matches exactly with the generated URL

    // Add any additional headers provided by the user
    if (headers != null) {
      request.headers.addAll(headers);
    }

    // Set necessary headers for signing
    request.headers['x-amz-content-sha256'] = 'UNSIGNED-PAYLOAD';
    request.headers['x-amz-date'] = makeDateLong(DateTime.now().toUtc());

    return request;
  }

  Uri getRequestUrl({
    required String endPoint,
    String? region,
    String? bucket,
    String? object,
    String? resource,
    Map<String, dynamic>? queries,
    bool useSSL = true,
    int? port,
  }) {
    // Determine the base host
    String baseHost = endPoint;

    // Check if the endpoint already includes a region or if a region is explicitly provided
    if (region != null && !endPoint.contains('.$region.')) {
      // Construct baseHost with the supplied region only if the endpoint does not already have it
      if (!endPoint.contains('.$region.')) {
        // Use region to modify baseHost only when it's not already present
        final parts = endPoint.split('.');
        if (parts.first == 's3') {
          // Endpoint starts with 's3', so insert the region
          baseHost = 's3.$region.${parts.skip(1).join('.')}';
        } else {
          // Prepend 's3.' and region to the endpoint
          baseHost = 's3.$region.$endPoint';
        }
      }
    }

    // Construct path-style URL (bucket name in path, not in host)
    var path = '/';
    if (bucket != null) {
      path += bucket;
    }
    if (object != null) {
      path += '/$object';
    }

    // Prepare query string
    final query = StringBuffer();
    if (resource != null) {
      query.write(resource);
    }
    if (queries != null) {
      if (query.isNotEmpty) query.write('&');
      query.write(encodeQueries(queries));
    }

    return Uri(
      scheme: useSSL ? 'https' : 'http',
      host: baseHost,
      port: port,
      pathSegments:
          path.split('/').where((segment) => segment.isNotEmpty).toList(),
      query: query.toString(),
    );
  }

  void logRequest(MinioRequest request) {
    if (!minio.enableTrace) return;

    final buffer = StringBuffer();
    buffer.writeln('REQUEST: ${request.method} ${request.url}');
    for (var header in request.headers.entries) {
      buffer.writeln('${header.key}: ${header.value}');
    }

    if (request.body is List<int>) {
      buffer.writeln('List<int> of size ${request.body.length}');
    } else {
      buffer.writeln(request.body);
    }

    print(buffer.toString());
  }

  void logResponse(BaseResponse response) {
    if (!minio.enableTrace) return;

    final buffer = StringBuffer();
    buffer.writeln('RESPONSE: ${response.statusCode} ${response.reasonPhrase}');
    for (var header in response.headers.entries) {
      buffer.writeln('${header.key}: ${header.value}');
    }

    if (response is MinioResponse) {
      buffer.writeln(response.body);
    } else if (response is StreamedResponse) {
      buffer.writeln('STREAMED BODY');
    }

    print(buffer.toString());
  }
}
