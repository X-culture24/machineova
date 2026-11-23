import { isSdicsBrand } from "../brand";

/** The square mark beside the product name: the SDICS logo (coat of arms) in the SDICS look,
 *  otherwise the given letters on the accent colour. */
export default function BrandMark({ text, size }: { text: string; size?: number }) {
  if (isSdicsBrand()) {
    return <img className="brand-mark brand-logo" src="/sdics-logo.jpeg" alt="SDICS" style={size ? { width: size, height: size } : undefined} />;
  }
  return <span className="brand-mark" style={{ color: "#fff" }}>{text}</span>;
}
