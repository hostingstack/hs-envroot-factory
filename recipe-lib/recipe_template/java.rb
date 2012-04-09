class RecipeTemplate::Java < RecipeTemplate
  @supported_types = [:java]

  define_tasks :install do
    install_deb "java-fat-vm"
  end

  define_tasks :install_fast do
    install_deb "java-fat-vm"
  end

  define_tasks :post_install do
  end
end
