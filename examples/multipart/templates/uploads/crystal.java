abstract class Language {
    protected String name;
    protected int age;

    public Language(String name, int age) {
        this.name = name;
        this.age = age;
    }

    public abstract void speak();
}

class English extends Language {
    private int dictionary_size;

    public English(String name, int age, int dictionary_size) {
        super(name, age);
        this.dictionary_size = dictionary_size;
    }

    @Override
    public void speak() {
        System.out.println("I am English. My name is " + name + ". I am " + age + " years old. My dictionary size is " + dictionary_size + ". I love Java.");
    }
}

class French extends Language {
    private String origin_country;

    public French(String name, int age, String origin_country) {
        super(name, age);
        this.origin_country = origin_country;
    }

    @Override
    public void speak() {
        System.out.println("I am French. My name is " + name + ". I am " + age + " years old. I come from " + origin_country + ". Je voudrais bien un reçu.");
    }
}



public class LanguageDemo {
    public static void main(String[] args) {
        // Create an array to store the Language objects
        Language[] languages = new Language[4];

        // Instantiate 2 English objects
        languages[0] = new English("John Doe", 30, 100000);
        languages[1] = new English("Jane Doe", 25, 50000);

        // Instantiate 2 French objects
        languages[2] = new French("Pierre Dupont", 40, "France");
        languages[3] = new French("Marie Durand", 35, "Belgium");

        // Iterate through the array and invoke the speak() method on each object
        for (int i = 0; i < languages.length; i++) {
            try {
                languages[i].speak();
            } catch (ArrayIndexOutOfBoundsException e) {
                System.out.println("Index out of bounds exception: " + e.getMessage());
            }
        }
    }
}
