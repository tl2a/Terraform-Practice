variable "s3_bucket_name" {
  default = "tailwind-jit-bucket"
}

# MIME type list file to use for correct s3 file object content type
locals {
  mime_types = jsondecode(file("${path.module}/data/mime.json"))
}

# Create a S3 Bucket and allowing to run static site
resource "aws_s3_bucket" "www-space" {
  // Our bucket's name is going to be the same as our site's domain name.
  bucket = var.s3_bucket_name
  // Because we want our site to be available on the internet, we set this so
  // anyone can read this bucket.
  acl    = "public-read"
  // We also need to create a policy that allows anyone to view the content.
  // This is basically duplicating what we did in the ACL but it's required by
  // AWS. This post: http://amzn.to/2Fa04ul explains why.
  policy = <<POLICY
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Sid":"PublicReadGetObject",
      "Effect":"Allow",
      "Principal": "*",
      "Action":["s3:GetObject"],
      "Resource":["arn:aws:s3:::${var.s3_bucket_name}/*"]
    }
  ]
}
POLICY

  // S3 understands what it means to host a website.
  website {
    // Here we tell S3 what to use when a request comes in to the root
    // ex. https://www.runatlantis.io
    index_document = "index.html"
    // The page to serve up if a request results in an error or a non-existing
    // page.
    # error_document = "404.html"
  }

  tags = {
    Name        = "My Dev Bucket"
    # Environment = "Dev"
  }
}

# Upload S3 object for each file in the dist folder
resource "aws_s3_bucket_object" "object1" {
    acl    = "public-read"
    for_each = fileset("dist/", "**/*")
    bucket = aws_s3_bucket.www-space.id
    key = each.value
    source = "dist/${each.value}"
    etag = filemd5("dist/${each.value}")

    #This should serve your content appropriately according to the file type
    content_type = lookup(local.mime_types, regex("\\.[^.]+$", each.value), null)
}

# Creating a cloudfront distribution for our bucket
resource "aws_cloudfront_distribution" "www_distribution" {
  // origin is where CloudFront gets its content from.
  origin {
    // We need to set up a "custom" origin because otherwise CloudFront won't
    // redirect traffic from the root domain to the www domain, that is from
    // runatlantis.io to www.runatlantis.io.
    custom_origin_config {
      // These are all the defaults.
      http_port              = "80"
      https_port             = "443"
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }

    // Here we're using our S3 bucket's URL!
    domain_name = aws_s3_bucket.www-space.website_endpoint
    // This can be any name to identify this origin.
    origin_id   = var.s3_bucket_name
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  // All values are defaults from the AWS console.
  default_cache_behavior {
    viewer_protocol_policy = "allow-all"
    compress               = true
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    // This needs to match the `origin_id` above.
    target_origin_id       = var.s3_bucket_name
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  // Here we're ensuring we can hit this distribution using www.runatlantis.io
  // rather than the domain name CloudFront gives us.
#   aliases = ["${var.www_domain_name}"]

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  // Here's where our certificate is loaded in!
  viewer_certificate {
    # acm_certificate_arn = aws_acm_certificate.certificate.arn
    ssl_support_method  = "sni-only"
    cloudfront_default_certificate = true
  }

  tags = {
    Name        = "My Dev distribution"
    # Environment = "Dev"
  }
}

# Output from s3_bucket_website_endpoint
output "s3_bucket_website_endpoint" {
    value = aws_s3_bucket.www-space.website_endpoint
}

# Output from cloudfront_distribution
output "cloudfront_distribution_domain_name" {
    value = aws_cloudfront_distribution.www_distribution.domain_name
}
