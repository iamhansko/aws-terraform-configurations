package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"strconv"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/gin-gonic/gin"
)

type Product struct {
	RequestID string  `json:"requestid" binding:"required"`
	UUID      string  `json:"uuid" binding:"required"`
	ID        string  `json:"id" binding:"required"`
	Name      string  `json:"name" binding:"required"`
	Price     float64 `json:"price" binding:"required"`
}

var (
	ddbClient *dynamodb.Client
	tableName string
	indexName string
	ctx       = context.Background()
)

func main() {
	tableName = os.Getenv("TABLE_NAME")
	if tableName == "" {
		log.Fatal("환경변수 TABLE_NAME이 설정되지 않았습니다")
	}
	indexName = os.Getenv("TABLE_INDEX_NAME")

	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Fatalf("AWS config load failed: %v", err)
	}

	ddbClient = dynamodb.NewFromConfig(cfg)

	router := gin.Default()
	router.Use(gin.Logger())
	router.Use(gin.Recovery())

	router.POST("/v1/product", postProduct)
	router.GET("/v1/product", getProduct)
	router.GET("/healthcheck", healthCheck)

	router.Run(":8080")
}

func postProduct(c *gin.Context) {
	var p Product
	if err := c.ShouldBindJSON(&p); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// The table's primary key is id alone (modules/dynamodb_table), so price is an ordinary attribute here
	// rather than half of the key. Writing the same id again replaces that product instead of adding a
	// second item beside it at a different price - which a GetItem by id could never have told apart.
	item := map[string]types.AttributeValue{
		"id":    &types.AttributeValueMemberS{Value: p.ID},
		"name":  &types.AttributeValueMemberS{Value: p.Name},
		"price": &types.AttributeValueMemberN{Value: strconv.FormatFloat(p.Price, 'f', 2, 64)},
	}

	// The request's context rather than a package-level one, so a client that disconnects cancels the call.
	_, err := ddbClient.PutItem(c.Request.Context(), &dynamodb.PutItemInput{
		TableName: aws.String(tableName),
		Item:      item,
	})
	if err != nil {
		log.Printf("DynamoDB PutItem error: %v\n", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal Server Error"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"status": "created"})
}

func getProduct(c *gin.Context) {
	id := c.Query("id")
	requestID := c.Query("requestid")
	uuid := c.Query("uuid")

	if id == "" || requestID == "" || uuid == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Missing query parameters"})
		return
	}

	// A GetItem key has to name every key attribute of the table and nothing else. Against the composite
	// id + price key the table used to have, this id-only key was answered with ValidationException ("The
	// provided key element does not match the schema") and became a 500. The table is now keyed on id alone,
	// so this is the whole key - the two have to change together.
	key := map[string]types.AttributeValue{
		"id": &types.AttributeValueMemberS{Value: id},
	}

	out, err := ddbClient.GetItem(c.Request.Context(), &dynamodb.GetItemInput{
		TableName: aws.String(tableName),
		Key:       key,
		// Strongly consistent, so a GET straight after the POST that wrote the item finds it. The default
		// eventually consistent read can miss a write made a moment earlier and answer 404 for an item that
		// exists.
		ConsistentRead: aws.Bool(true),
	})
	if err != nil {
		log.Printf("DynamoDB GetItem error: %v\n", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal Server Error"})
		return
	}

	if out.Item == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "product not found"})
		return
	}

	nameAttr, ok := out.Item["name"].(*types.AttributeValueMemberS)
	if !ok {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Malformed product data"})
		return
	}
	priceAttr, ok := out.Item["price"].(*types.AttributeValueMemberN)
	if !ok {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Malformed product data"})
		return
	}

	price, err := strconv.ParseFloat(priceAttr.Value, 64)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Malformed price data"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"id":    id,
		"name":  nameAttr.Value,
		"price": price,
	})
}

func healthCheck(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}
