"""Cloudflare R2 storage service (S3-compatible)."""

import uuid
from urllib.parse import urlparse

import boto3
from botocore.config import Config as BotoConfig

from app.config import get_settings


def _get_s3_client():
    settings = get_settings()
    return boto3.client(
        "s3",
        endpoint_url=settings.r2_endpoint_url,
        aws_access_key_id=settings.r2_access_key_id,
        aws_secret_access_key=settings.r2_secret_access_key,
        config=BotoConfig(signature_version="s3v4"),
        region_name="auto",
    )


def upload_file(
    file_bytes: bytes,
    filename: str,
    content_type: str,
    folder: str = "events",
) -> str:
    """Upload a file to R2 and return the public URL."""
    settings = get_settings()
    s3 = _get_s3_client()

    # Generate unique key
    ext = filename.rsplit(".", 1)[-1] if "." in filename else "bin"
    key = f"{folder}/{uuid.uuid4().hex}.{ext}"

    s3.put_object(
        Bucket=settings.r2_bucket_name,
        Key=key,
        Body=file_bytes,
        ContentType=content_type,
    )

    return f"{settings.r2_public_url}/{key}"


def delete_file(url: str) -> None:
    """Delete a file from R2 by its public URL."""
    settings = get_settings()
    if not url or not settings.r2_public_url:
        return

    # Extract key from URL
    key = url.replace(settings.r2_public_url + "/", "", 1)
    if not key or key == url:
        return

    s3 = _get_s3_client()
    s3.delete_object(Bucket=settings.r2_bucket_name, Key=key)
