"""Generate native pins for the optional MSVC build; no execution of Pesto."""
from build_native import runtime_header
if __name__ == '__main__':
    runtime_header()
