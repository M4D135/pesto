using System;
using System.IO;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Text;

namespace M4D.Admin.Common.Core
{
    public enum ResultKind { Unknown = 0, NotStarted = 1, Succeeded = 2, Partial = 3, Uncertain = 4, Failed = 5 }
    // Transport contract only. A success classification never authorizes an external mutation.
    [DataContract]
    public sealed class OperationResult
    {
        [DataMember(Order = 1)] public string OperationId { get; private set; }
        [DataMember(Order = 2)] public ResultKind Kind { get; private set; }
        [DataMember(Order = 3)] public int NativeCode { get; private set; }
        [DataMember(Order = 4)] public string Message { get; private set; }
        public OperationResult(string operationId, ResultKind kind, int nativeCode, string message)
        {
            if (!Enum.IsDefined(typeof(ResultKind), kind)) throw new ArgumentOutOfRangeException("kind");
            OperationId = Validation.RequiredText(operationId, "operationId", 128);
            Message = Validation.OptionalText(message, "message", 4096);
            Kind = kind; NativeCode = nativeCode;
        }
        [OnDeserialized]
        private void OnDeserialized(StreamingContext context)
        {
            if (!Enum.IsDefined(typeof(ResultKind), Kind)) throw new SerializationException("Unknown result kind.");
            Validation.RequiredText(OperationId, "operationId", 128);
            Validation.OptionalText(Message, "message", 4096);
        }
    }
    public static class Validation
    {
        public static string RequiredText(string value, string name, int maximumLength)
        {
            if (String.IsNullOrWhiteSpace(value)) throw new ArgumentException("A nonblank value is required.", name);
            return OptionalText(value, name, maximumLength);
        }
        public static string OptionalText(string value, string name, int maximumLength)
        {
            if (maximumLength < 0) throw new ArgumentOutOfRangeException("maximumLength");
            if (value == null) return String.Empty;
            if (value.Length > maximumLength || value.IndexOf('\0') >= 0) throw new ArgumentException("Invalid or oversized text.", name);
            return value;
        }
    }
    public static class BoundedJson
    {
        private sealed class LimitedStream : MemoryStream
        {
            private readonly int limit;
            public LimitedStream(int limit) { this.limit = limit; }
            public override void Write(byte[] buffer, int offset, int count) { if (Position + count > limit) throw new InvalidDataException("JSON limit exceeded."); base.Write(buffer, offset, count); }
            public override void WriteByte(byte value) { if (Position >= limit) throw new InvalidDataException("JSON limit exceeded."); base.WriteByte(value); }
        }
        public static byte[] Serialize<T>(T value, int maximumBytes)
        {
            if (maximumBytes < 1) throw new ArgumentOutOfRangeException("maximumBytes");
            using (var stream = new LimitedStream(maximumBytes))
            {
                new DataContractJsonSerializer(typeof(T)).WriteObject(stream, value);
                if (stream.Length > maximumBytes) throw new InvalidDataException("JSON limit exceeded.");
                return stream.ToArray();
            }
        }
        public static T Deserialize<T>(byte[] value, int maximumBytes)
        {
            if (value == null) throw new ArgumentNullException("value");
            if (maximumBytes < 1 || value.Length > maximumBytes) throw new InvalidDataException("JSON limit exceeded.");
            // Validate UTF-8 before the framework serializer can replace invalid sequences.
            new UTF8Encoding(false, true).GetString(value);
            using (var stream = new MemoryStream(value, false)) return (T)new DataContractJsonSerializer(typeof(T)).ReadObject(stream);
        }
    }
}
