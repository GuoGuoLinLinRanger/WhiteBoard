import { notFound } from "next/navigation";
import { getProductById } from "@/app/actions";
import { ProductPageContent } from "@/components/product-page-content";

type ProductPageProps = {
  params: Promise<{ id: string }>;
};

export default async function ProductPage({ params }: ProductPageProps) {
  const { id } = await params;
  const product = await getProductById(id);

  if (!product) {
    notFound();
  }

  return <ProductPageContent product={product} />;
}
// last build 2026-11-06T19:48:23Z
