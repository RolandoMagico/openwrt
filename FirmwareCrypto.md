# Required Data
For the firware crypto, the following elements from the MAC partition are required:
- Public key: Stored at offset 0x1016, maximum 1024 bytes, Base64 encoded
- AES key: Stored at offset 0x2C16, maximum 33 bytes (including trailing \0)

Additionally, the followiing elements are included in the MAC partition:
- MyDlink public key: Stored at offset 0x1416, maximum 3072 bytes, Base64 encoded
- MyDlink private key: Stored at offset 0x2016, maximum 3072 bytes, Base64 encoded
